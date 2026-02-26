"""
Validator carousel:
1. Finds the validator ranked at the bottom of the validator set (including inactive validators).
2. Each block, a playmaker account delegates enough tokens to it to make it climb to spot x on the validator list.
3. The application keeps going until it is stopped.

"""

import argparse
import json
import logging
import subprocess
import asyncio
from typing import List, Dict, Any, Optional
import websockets
import requests
import urllib
from time import sleep


logging.basicConfig(
    filename=None,
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)

class ValidatorCarousel():
    """Manages validator rotations through delegation operations."""
    
    # Constants
    ACCOUNT_MINIMUM = 50_000_000  # 50 tokens
    ROTATION_DELTA = 10_000_000  # 10 tokens
    SWAP_DELTA = 1_000_000  # 1 token
    PRE_FUNDING_AMOUNT = 10_000_000_000  # 10,000 tokens
    WEBSOCKET_MAX_SIZE = 100 * 1024 * 1024  # 100MB
    WEBSOCKET_DELAY = 0.2  # seconds
    RECONNECT_DELAY = 3  # seconds
    
    def __init__(
        self,
        urlAPI: str,
        urlRPC: str,
        binary: str,
        chain: str,
        home: str,
        denom: str,
        delegator: str,
        target_rank: int,
        no_rotation: bool,
        up_rotation: bool,
        swap_consensus: bool,
        swap_bonded: bool,
        redelegate: bool,
        height: int,
        operations_filename: str
    ) -> None:
        self.urlAPI = urlAPI
        self.urlRPC = urlRPC
        self.binary = binary
        self.chain = chain
        self.home = home
        self.denom = denom
        self.delegator = delegator
        self.target_rank = target_rank
        self.no_rotation = no_rotation
        self.up_rotation = up_rotation
        self.swap_consensus = swap_consensus
        self.swap_bonded = swap_bonded
        self.redelegate = redelegate
        self.target_height = height
        self.operations_filename = operations_filename
        self.operations: List[Dict[str, Any]] = []
        self._validators_by_vp: List[Dict[str, Any]] = []
        self.account_balance = 0
        self.height = 0

    def api_get_validators(self, urlAPI, height: int = 0):
        """
        Collects the validators info at the specified height
        - operator address in cosmosvaloper format
        - consensus pubkey
        - jailed status
        - tokens
        - delegator shares
        - moniker
        - and more
        """
        if height > 0:
            response = requests.get(
                f"{urlAPI}/cosmos/staking/v1beta1/validators?pagination.limit=1000",
                headers={"x-cosmos-block-height": f"{height}"},
            ).json()
        else:
            response = requests.get(f"{urlAPI}/cosmos/staking/v1beta1/validators").json()
        # total = int(response["pagination"]["total"])
        if 'code' in response and response['code'] != 0:
            logging.error(f"Error fetching validators: {response['message']}")
            return []
        api_vals = response["validators"]
        next_key = response["pagination"]["next_key"]
        while next_key:
            response = requests.get(
                f"{urlAPI}/cosmos/staking/v1beta1/validators?pagination.limit=1000&pagination.key="
                f"{urllib.parse.quote(next_key)}",
                headers={"x-cosmos-block-height": f"{height}"},
            ).json()
            api_vals.extend(response["validators"])
            next_key = response["pagination"]["next_key"]
        return api_vals

    def api_get_provider_params(self, urlAPI: str, height: int = 0):
        """
        Returns the info array
        """
        endpoint = f"{urlAPI}/interchain_security/ccv/provider/params"
        if height:
            response = requests.get(
                endpoint, headers={"x-cosmos-block-height": f"{height}"}
            ).json()
        else:
            response = requests.get(endpoint).json()
        if "params" in response:
            return response["params"]
        return []


    def api_get_staking_params(self, urlAPI: str, height: int = 0):
        """
        Returns the info array
        """
        endpoint = f"{urlAPI}/cosmos/staking/v1beta1/params"
        if height:
            response = requests.get(
                endpoint, headers={"x-cosmos-block-height": f"{height}"}
            ).json()
        else:
            response = requests.get(endpoint).json()
        if "params" in response:
            return response["params"]
        return []

    def delegate_message_json(self, del_addr, val_addr, amount, denom: str = "uatom"):
        return {
            "@type": "/cosmos.staking.v1beta1.MsgDelegate",
            "delegator_address": del_addr,
            "validator_address": val_addr,
            "amount": {"denom": str(denom), "amount": str(amount)},
        }


    def redelegate_message_json(self, 
        del_addr, src_addr, dst_addr, amount, denom: str = "uatom"
    ):
        return {
            "@type": "/cosmos.staking.v1beta1.MsgBeginRedelegate",
            "delegator_address": del_addr,
            "validator_src_address": src_addr,
            "validator_dst_address": dst_addr,
            "amount": {"denom": str(denom), "amount": str(amount)},
        }



    def undelegate_message_json(self, del_addr, val_addr, amount, denom: str = "uatom"):
        return {
            "@type": "/cosmos.staking.v1beta1.MsgUndelegate",
            "delegator_address": del_addr,
            "validator_address": val_addr,
            "amount": {"denom": str(denom), "amount": str(amount)},
        }


    def transaction_json(
        self,
        messages: list,
        gas_prices: float = 0.005,
        fee_denom: str = "uatom",
        gas_limit: int = 1000000,
        memo: str = "",
    ):
        fee_amount = int(gas_limit * gas_prices)
        return {
            "body": {
                "messages": messages,
                "memo": memo,
                "timeout_height": "0",
                "extension_options": [],
                "non_critical_extension_options": [],
            },
            "auth_info": {
                "signer_infos": [],
                "fee": {
                    "amount": [{"denom": str(fee_denom), "amount": str(fee_amount)}],
                    "gas_limit": str(gas_limit),
                    "payer": "",
                    "granter": "",
                },
            },
        }

    def update_account_balance(self) -> None:
        """Update the account balance and exit if below minimum."""
        result = subprocess.run(
            [self.binary, 'q', 'bank', 'balances',
             self.delegator,
             f'--node={self.urlRPC}',
             f'--chain-id={self.chain}',
             '--output=json'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True
        )
        try:
            result.check_returncode()
            response = json.loads(result.stdout)
            self.account_balance = int(response['balances'][0]['amount'])
            logging.info(f'The account has {self.account_balance}{response["balances"][0]["denom"]}.')
            if self.account_balance < self.ACCOUNT_MINIMUM:
                logging.info("The account balance has decreased below the specified minimum, stopping now.")
                exit()
        except subprocess.CalledProcessError as cpe:
            logging.error(f"{cpe}\n{result.stderr}")


    def sort_vals_by_vp(self) -> None:
        """Sort validators by voting power (includes inactive validators)."""
        val_list = self.api_get_validators(self.urlAPI)
        self._validators_by_vp = sorted(val_list, key=lambda val: int(val['tokens']), reverse=True)

    def _create_swap_operation(
        self, 
        cap: int, 
        set_type: str, 
        use_redelegate: bool
    ) -> Optional[Dict[str, Any]]:
        """
        Generic method to create swap operations for consensus or bonded sets.
        
        Args:
            cap: The maximum validator cap for the set
            set_type: Type of set ('consensus' or 'bonded')
            use_redelegate: Whether to use redelegate instead of delegate
            
        Returns:
            Operation dictionary or None if no swap is needed
        """
        if len(self._validators_by_vp) <= cap:
            return None
            
        source_val = self._validators_by_vp[cap]
        target_val = self._validators_by_vp[cap - 1]
        
        if use_redelegate:
            operation = 'redelegate'
            amount = int(target_val['tokens']) - int(source_val['tokens']) + self.SWAP_DELTA
            logging.info(
                f'Setting operation to redelegate {amount} from '
                f'{target_val["description"]["moniker"]} to '
                f'{source_val["description"]["moniker"]}.'
            )
            return {
                'from_validator': target_val,
                'to_validator': source_val,
                'op': operation,
                'amount': amount
            }
        else:
            operation = 'delegate'
            amount = int(target_val['tokens']) - int(source_val['tokens']) + self.SWAP_DELTA
            logging.info(
                f'Setting operation to delegate {amount} to '
                f'{source_val["description"]["moniker"]} to replace '
                f'{target_val["description"]["moniker"]}.'
            )
            return {
                'validator': source_val,
                'op': operation,
                'amount': amount
            }

    def swap_consensus_op(self) -> Optional[Dict[str, Any]]:
        """
        Swap the validator at the bottom of the consensus set with the one below it.
        
        Returns:
            Operation dictionary or None if no swap is needed
        """
        provider_params = self.api_get_provider_params(self.urlAPI)
        if not provider_params:
            logging.warning("Failed to fetch provider params, skipping swap-consensus operation.")
            return None
        consensus_cap = int(provider_params['max_provider_consensus_validators'])
        return self._create_swap_operation(consensus_cap, 'consensus', False)
    
    def swap_consensus_redel_op(self) -> Optional[Dict[str, Any]]:
        """
        Swap consensus validators using redelegation.
        
        Returns:
            Operation dictionary or None if no swap is needed
        """
        provider_params = self.api_get_provider_params(self.urlAPI)
        if not provider_params:
            logging.warning("Failed to fetch provider params, skipping swap-consensus-redel operation.")
            return None
        consensus_cap = int(provider_params['max_provider_consensus_validators'])
        return self._create_swap_operation(consensus_cap, 'consensus', True)

    def swap_bonded_op(self) -> Optional[Dict[str, Any]]:
        """
        Swap the validator at the bottom of the bonded set with the one below it.
        
        Returns:
            Operation dictionary or None if no swap is needed
        """
        staking_params = self.api_get_staking_params(self.urlAPI)
        bonded_cap = int(staking_params['max_validators'])
        return self._create_swap_operation(bonded_cap, 'bonded', False)

    def swap_bonded_op_redel(self) -> Optional[Dict[str, Any]]:
        """
        Swap bonded validators using redelegation.
        
        Returns:
            Operation dictionary or None if no swap is needed
        """
        staking_params = self.api_get_staking_params(self.urlAPI)
        bonded_cap = int(staking_params['max_validators'])
        return self._create_swap_operation(bonded_cap, 'bonded', True)

    def set_operations(self) -> None:
        """Determine and set the operations to be performed based on configured rotation mode."""
        self.sort_vals_by_vp()
        self.operations = []

        if self.up_rotation:
            # The validator at the target rank will take the place of the validator with the least amount of voting power.
            source_val = self._validators_by_vp[self.target_rank]
            target_val = self._validators_by_vp[-1]
            operation = 'unbond'
            amount = int(source_val['tokens']) - int(target_val['tokens']) + self.ROTATION_DELTA
            logging.info(
                f'Setting operation to unbond {amount} from '
                f'{source_val["description"]["moniker"]} to replace '
                f'{target_val["description"]["moniker"]}.'
            )
            self.operations.append({
                'validator': source_val,
                'op': operation,
                'amount': amount
            })

        elif not self.no_rotation:
            # The validator with the least amount of voting power will take the place of the validator at the target rank.
            source_val = self._validators_by_vp[-1]
            target_val = self._validators_by_vp[self.target_rank]
            operation = 'delegate'
            amount = int(target_val['tokens']) - int(source_val['tokens']) + self.ROTATION_DELTA
            logging.info(
                f'Setting operation to delegate {amount} to '
                f'{source_val["description"]["moniker"]} to replace '
                f'{target_val["description"]["moniker"]}.'
            )
            self.operations.append({
                'validator': source_val,
                'op': operation,
                'amount': amount
            })
        
        if self.swap_consensus:
            if self.redelegate:
                swap_operation = self.swap_consensus_redel_op()
            else:
                swap_operation = self.swap_consensus_op()
            if swap_operation:
                self.operations.append(swap_operation)
            
        if self.swap_bonded:
            if self.redelegate:
                swap_operation = self.swap_bonded_op_redel()
            else:
                swap_operation = self.swap_bonded_op()
            if swap_operation:
                self.operations.append(swap_operation)


    def sign(self) -> None:
        """Sign the transaction using the delegator's key."""
        result = subprocess.run(
            [self.binary, 'tx', 'sign', 'tx.json',
             f'--from={self.delegator}',
             f'--node={self.urlRPC}',
             f'--chain-id={self.chain}',
             '--output-document=tx-signed.json',
             '--output=json',
             f'--home={self.home}',
             '-y'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True
        )
        try:
            result.check_returncode()
        except subprocess.CalledProcessError as cpe:
            logging.error(f"{cpe}\n{result.stderr}")

    def broadcast(self) -> None:
        """Broadcast the signed transaction to the network."""
        result = subprocess.run(
            [self.binary, 'tx', 'broadcast', 'tx-signed.json',
             f'--node={self.urlRPC}',
             f'--chain-id={self.chain}',
             '--output=json',
             '-y'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True
        )
        print(result.stdout)
        try:
            result.check_returncode()
        except subprocess.CalledProcessError as cpe:
            logging.error(f"{cpe}\n{result.stderr}")

    def record_operations(self) -> None:
        """
        Record all operations performed in a block to a JSON file.
        
        The file structure is:
        {
            "rotations": {
                "<block_height>": {
                    "operations": [<operation>, ...]
                }
            }
        }
        """
        if not self.operations:
            return
            
        # Load existing data or create new structure
        try:
            with open(self.operations_filename, 'r') as f:
                data = json.load(f)
        except FileNotFoundError:
            data = {'rotations': {}}
        except json.JSONDecodeError:
            logging.warning(f"Invalid JSON in {self.operations_filename}, starting with empty data")
            data = {'rotations': {}}
            
        # Prepare operations for this block
        block_operations = {'operations': []}
        for operation in self.operations:
            block_operations['operations'].append(operation)
            
        # Record operations for this block height
        data['rotations'][str(self.height)] = block_operations
        
        # Write back to file
        try:
            with open(self.operations_filename, 'w') as f:
                json.dump(data, f, indent=2)
            logging.info(
                f"Recorded {len(block_operations['operations'])} operations for "
                f"block {self.height} to {self.operations_filename}"
            )
        except IOError as e:
            logging.error(f"Failed to write operations to {self.operations_filename}: {e}")



    def rotate(self) -> None:
        """
        Execute validator rotation by building, signing, and broadcasting delegation transactions.
        
        This method:
        1. Checks account balance
        2. Determines operations to perform
        3. Builds transaction messages
        4. Signs and broadcasts the transaction
        5. Records the operations
        """
        # Check balance and exit if below minimum
        self.update_account_balance()
        if self.account_balance < self.ACCOUNT_MINIMUM:
            logging.info("The account balance has decreased below the specified minimum, stopping now.")
            exit()

        # Identify operations to perform
        self.set_operations()
        if not self.operations:
            logging.info("No operations available, skipping rotation.")
            return

        # Build transaction messages
        messages = []
        for operation in self.operations:
            if operation['op'] == 'unbond':
                messages.append(self.undelegate_message_json(
                    del_addr=self.delegator,
                    val_addr=operation['validator']['operator_address'],
                    amount=operation['amount'],
                    denom=self.denom
                ))
            elif operation['op'] == 'delegate':
                if operation['amount'] > self.account_balance:
                    logging.info('The required delegation amount is more than the available funds, stopping now.')
                    exit()
                messages.append(self.delegate_message_json(
                    del_addr=self.delegator,
                    val_addr=operation['validator']['operator_address'],
                    amount=operation['amount'],
                    denom=self.denom
                ))
            elif operation['op'] == 'redelegate':
                messages.append(self.redelegate_message_json(
                    del_addr=self.delegator,
                    src_addr=operation['from_validator']['operator_address'],
                    dst_addr=operation['to_validator']['operator_address'],
                    amount=operation['amount'],
                    denom=self.denom
                ))
        
        # Build, sign, and broadcast transaction
        tx_json = self.transaction_json(messages=messages)
        with open('tx.json', 'w') as f:
            json.dump(tx_json, f, indent=4)
        self.sign()
        self.broadcast()
        self.record_operations()

    async def subscribe(self, reconnect_delay: int = RECONNECT_DELAY) -> None:
        """
        Subscribe to Tendermint RPC websocket for NewBlock events and execute rotations.
        
        This method:
        - Connects to the RPC websocket endpoint
        - Pre-funds validators if needed for upward rotations or redelegations
        - Listens for new blocks and triggers rotations
        - Handles reconnection on connection loss
        
        Args:
            reconnect_delay: Number of seconds to wait before reconnecting (default: 3)
        """
        WS_NEWBLOCK_SUBSCRIPTION = (
            '{ "jsonrpc": "2.0", "method": "subscribe", '
            '"params": ["tm.event=\'NewBlock\'"], "id": 1 }'
        )
        ws_url = self.urlRPC.replace('http', 'ws').replace('https', 'wss') + '/websocket'
        
        # Pre-fund validators if needed for upward rotations or redelegations
        if self.up_rotation or self.redelegate:
            logging.info("> Pre-funding all validators with delegations to enable upward rotations.")
            val_list = self.api_get_validators(self.urlAPI)
            messages = []
            for val in val_list:
                messages.append(self.delegate_message_json(
                    del_addr=self.delegator,
                    val_addr=val['operator_address'],
                    amount=self.PRE_FUNDING_AMOUNT,
                    denom=self.denom
                ))
            tx_json = self.transaction_json(messages=messages)
            with open('tx.json', 'w') as f:
                json.dump(tx_json, f, indent=4)
            self.sign()
            self.broadcast()

        while True:
            try:
                async with websockets.connect(
                    ws_url, 
                    max_size=self.WEBSOCKET_MAX_SIZE
                ) as websocket:
                    logging.info("Connected to websocket endpoint: %s", ws_url)
                    await websocket.send(WS_NEWBLOCK_SUBSCRIPTION)
                    await websocket.recv()
                    
                    while True:
                        ws_data = json.loads(await websocket.recv())
                        
                        # Check if result exists in response
                        if 'result' not in ws_data:
                            logging.warning("Unexpected websocket data format: %s", ws_data)
                            continue
                            
                        block = ws_data['result']['data']['value']['block']
                        sleep(self.WEBSOCKET_DELAY)
                        logging.info('New block: %s', block['header']['height'])
                        self.height = int(block['header']['height'])
                        
                        if not self.target_height:
                            self.rotate()
                            continue

                        if self.height > self.target_height:
                            logging.info(f"Passed target height of {self.target_height}, stopping now.")
                            exit(0)

                        if self.height == self.target_height:
                            self.rotate()
                            logging.info(f"Reached target height of {self.target_height}, stopping now.")
                            exit(0)
                        
            except websockets.exceptions.ConnectionClosedError as cce:
                logging.error("Connection Closed Error: %s", cce)
                logging.info("Reconnecting in %d seconds...", reconnect_delay)
                await asyncio.sleep(reconnect_delay)
            except (websockets.exceptions.WebSocketException, OSError, ConnectionError) as e:
                logging.error("Connection Error: %s", e)
                logging.info("Reconnecting in %d seconds...", reconnect_delay)
                await asyncio.sleep(reconnect_delay)
            except KeyError as ke:
                logging.error("Key Error processing websocket data: %s", ke)
                logging.info("Reconnecting in %d seconds...", reconnect_delay)
                await asyncio.sleep(reconnect_delay)
            except json.JSONDecodeError as jde:
                logging.error("JSON Decode Error: %s", jde)
                logging.info("Reconnecting in %d seconds...", reconnect_delay)
                await asyncio.sleep(reconnect_delay)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Get validator set information')
    parser.add_argument('--api', type=str, default='http://localhost:25001', 
                        help='API endpoint URL (default: http://localhost:25001)')
    parser.add_argument('--rpc', type=str, default='http://localhost:27001',
                        help='RPC endpoint URL (default: http://localhost:27001)')
    parser.add_argument('--binary', type=str, default='gaiad',
                        help='Binary name (default: gaiad)')
    parser.add_argument('--home', type=str, default='~/.gaia',
                        help='Home directory for the binary (default: ~/.gaia)')
    parser.add_argument('--chain-id', type=str, default='testnet',
                        help='Chain ID (default: testnet)')
    parser.add_argument('--denom', type=str, default='uatom',
                        help='Denom for delegations (default: uatom)')
    parser.add_argument('--delegator', type=str, default='cosmos1r5v5srda7xfth3hn2s26txvrcrntldjumt8mhl',
                        help='Delegator address for delegations (default: cosmos1r5v5srda7xfth3hn2s26txvrcrntldjumt8mhl)')
    parser.add_argument('--target-rank', type=int, default=1,
                        help='Target rank for the validator carousel (default: 1)')
    parser.add_argument('--no-rotation', action='store_true',
                        help='Disables the full set rotation and only executes the specified swap operations if any (default: False)')
    parser.add_argument('--up-rotation', action='store_true',
                        help='Sets up an up rotation that unbonds tokens from the delegator')
    parser.add_argument('--swap-consensus', action='store_true',
                        help='Sets up a rotation that swaps the validator at the bottom of the consensus set with the validator above it')
    parser.add_argument('--swap-bonded', action='store_true',
                        help='Sets up a rotation that swaps the validator at the bottom of the bonded set with the validator above it')
    parser.add_argument('--redelegate', action='store_true',
                        help='Sets up a rotation that redelegates tokens instead of delegating them, applies to swap-consensus and swap-bonded operations')
    parser.add_argument('--height', type=int, default=0,
                        help='Target height to submit the rotation (default: 0 for no stop)')
    parser.add_argument('--rotations', type=str, default='rotations.json',
                        help='Rotations JSON file (default: rotations.json)')
    args = parser.parse_args()

    carousel = ValidatorCarousel(
        urlAPI=args.api,
        urlRPC=args.rpc,
        binary=args.binary,
        home=args.home,
        chain=args.chain_id,
        denom=args.denom,
        delegator=args.delegator,
        target_rank=args.target_rank,
        no_rotation=args.no_rotation,
        up_rotation=args.up_rotation,
        swap_consensus=args.swap_consensus,
        swap_bonded=args.swap_bonded,
        redelegate=args.redelegate,
        height=args.height,
        operations_filename=args.rotations
    )
    asyncio.run(carousel.subscribe())