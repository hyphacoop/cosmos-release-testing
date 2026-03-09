"""
Validator Set Compare
Compares two validator sets based on the transactions between them and verifies that the resulting changes are correct.
If the upgrade flag is set to true to signal ICS removal, the script will check that the max_provider_consensus_validators param at the starting height matches the max_validators param on the following block.

1. Provider and staking parameters (max provider consensus validators and max validators)
2. Comet validator set information
    - pubkey
    - voting power
    - rank
3. Bonded tokens per validator
4. Voting power per validator based on bonded tokens and total bonded tokens
5. Total bonded tokens
6. Total number of validators in comet validator set
7. Total number of validators (bonded and unbonded)
8. Number of bonded validators
9. Validator rank by voting power
10. Validator status (active/inactive based on max validators and bonded status)

Required inputs:
- Starting height
- Rotations JSON file

The script will then fetch the validator set information at:
- Block N-2 (rotations from this block will affect the comet validator set block N+1)
- Block N-1
- Block N (the rotations go in)
- Block N+1 (rotations are applied)
- Block N+2
- Block N+3 (comet validator set is updated)
"""

from logging import exception
import argparse
import json
import logging
import requests
import copy
import urllib


logging.basicConfig(
    filename=None,
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)

def api_get_provider_params(urlAPI: str, height: int = 0):
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
    # logging.info(f'Response from provider params endpoint: {response}')
    if "params" in response:
        return response["params"]
    return []

def api_get_staking_params(urlAPI: str, height: int = 0):
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
    # logging.info(f'Response from staking params endpoint: {response}')
    if "params" in response:
        return response["params"]
    return []


def api_get_staking_pool(urlAPI: str, height: int = 0):
    """
    Returns the info array
    """
    endpoint = f"{urlAPI}/cosmos/staking/v1beta1/pool"
    if height:
        response = requests.get(
            endpoint, headers={"x-cosmos-block-height": f"{height}"}
        ).json()
    else:
        response = requests.get(endpoint).json()
    if "pool" in response:
        return response["pool"]
    return []

def api_get_validators(urlAPI, height: int = 0):
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

def rpc_get_block_results(urlRPC, height):
    response = requests.get(f"{urlRPC}/block_results?height={height}").json()
    if 'result' not in response:
        return {}
    return response['result']

def rpc_get_current_height(urlRPC: str):
    """
    Returns the current block height from the RPC endpoint.
    """
    response = requests.get(f"{urlRPC}/status").json()
    return int(response["result"]["sync_info"]["latest_block_height"])


def rpc_get_validators(urlRPC, height: int = 0):
    """
    Collects validators info at the latest block height
    - Address in bytes format
    - pubkey
    - voting power
    - proposer priority
    """
    page = 1
    if height > 0:
        response = requests.get(
            f"{urlRPC}/validators?page={page}&height={height}"
        ).json()["result"]
    else:
        response = requests.get(f"{urlRPC}/validators?page={page}").json()["result"]
    val_count = int(response["count"])
    total = int(response["total"])
    rpc_vals = response["validators"]

    while val_count < total:
        page += 1
        if height > 0:
            response = requests.get(
                f"{urlRPC}/validators?page={page}&height={height}"
            ).json()["result"]
        else:
            response = requests.get(f"{urlRPC}/validators?page={page}").json()["result"]
        val_count += int(response["count"])
        rpc_vals.extend(response["validators"])
    # print(f'Collected {len(rpc_vals)} validators via RPC.')
    return rpc_vals


class ValsetInfo():
    def __init__(self,
                urlAPI: str='http://localhost:25001',
                urlRPC: str='http://localhost:27001',
                binary: str='gaiad',
                height: int=0,
                output_prefix: str='valset-info',
                check_prefix: str='valset-check'):
        
        self.urlAPI = urlAPI
        self.urlRPC = urlRPC
        self.binary = binary
        self.height = height
        self.output_prefix = output_prefix
        self.check_prefix = check_prefix
        self.data = {
            'height': self.height,
            'ics_enabled': True,
        }

    def get_provider_params(self):
        params = api_get_provider_params(self.urlAPI, height=self.height)
        if not params:
            logging.error("Error fetching provider params")
            self.data['provider_validators'] = None
            self.data['ics_enabled'] = False
            return
        self.data['provider_validators'] = int(params['max_provider_consensus_validators'])

    def get_staking_params(self):
        params = api_get_staking_params(self.urlAPI, height=self.height)
        if not params:
            logging.error("Error fetching staking params")
            exit()
        self.data['staking_validators'] = int(params['max_validators'])

    def get_staking_pool(self):
        pool = api_get_staking_pool(self.urlAPI, height=self.height)
        self.data['staking_pool'] = {
            'bonded_tokens': int(pool['bonded_tokens']),
            'not_bonded_tokens': int(pool['not_bonded_tokens'])
        }

    def get_comet_validator_set(self):
        val_list = rpc_get_validators(self.urlRPC, self.height)
        self.data['comet_validator_set'] = {}
        for index, val in enumerate(val_list):
            self.data['comet_validator_set'][val['pub_key']['value']] = {
                'address': val['address'],
                'voting_power': int(val['voting_power']),
                'rank': index + 1  # Ranks start at 1
            }
        self.data['comet_validator_set_size'] = len(val_list)
        self.data['comet_total_voting_power'] = sum(float(val['voting_power']) for val in val_list)

    def get_validator_info(self):
        val_list = api_get_validators(self.urlAPI, height=self.height)
        total_bonded_validators = 0
        total_bonded_tokens = 0
        total_active_bonded_tokens = 0
        validator_info = []
        for val in val_list:
            pubkey = val['consensus_pubkey']['key']
            new_validator = {
                'moniker': val['description']['moniker'],
                'operator_address': val['operator_address'],
                'bonded': val['status'],
                'tokens': int(val['tokens']),
                'pubkey': pubkey,
                'jailed': val['jailed']
            }
            if pubkey in self.data['comet_validator_set']:
                new_validator['comet_vp'] = int(
                    self.data['comet_validator_set'][pubkey]['voting_power']
                )
                new_validator['comet_vp_fraction'] = int(
                    self.data['comet_validator_set'][pubkey]['voting_power'])/self.data['comet_total_voting_power']
                new_validator['comet_rank'] = \
                    self.data['comet_validator_set'][pubkey]['rank']
                new_validator['active'] = True
            else:
                new_validator['comet_vp'] = 0.0
                new_validator['comet_vp_fraction'] = 0.0
                new_validator['comet_rank'] = None
                new_validator['active'] = False
            if val['status'] == 'BOND_STATUS_BONDED':
                total_bonded_validators += 1
                total_bonded_tokens += int(val['tokens'])
                if new_validator['active']:
                    total_active_bonded_tokens += int(val['tokens'])
            validator_info.append(new_validator)
        for v in validator_info:
            # Calculate voting power based on bonded tokens and total bonded tokens
            if not v['active']:
                v['tokens_vp_fraction'] = 0
                continue
            v['tokens_vp_fraction'] = int(v['tokens']/1000000)/int(total_active_bonded_tokens/1000000) # Must clip 1E6 decimals to avoid issues when comparing to comet vp fraction, which calculates with clipped amounts

        # Sort validator_info by tokens descending
        validator_info.sort(key=lambda v: v['tokens'], reverse=True)

        # Stage data for saving
        self.data['validator_info'] = validator_info
        self.data['total_bonded_tokens'] = total_bonded_tokens
        self.data['total_active_bonded_tokens'] = total_active_bonded_tokens
        self.data['total_bonded_validators'] = total_bonded_validators

    def self_check(self):
        issues = []
        
        # Check 1: bonded_tokens must equal total bonded tokens in staking pool
        if self.data['total_bonded_tokens'] != self.data['staking_pool']['bonded_tokens']:
            issue = f"❌ BONDED TOKENS MISMATCH: Validator info shows {self.data['total_bonded_tokens']} but staking pool shows {self.data['staking_pool']['bonded_tokens']}"
            issues.append(issue)
            logging.warning(f"❌ Total bonded tokens from validator info ({self.data['total_bonded_tokens']}) \
                            does not match bonded tokens from staking pool ({self.data['staking_pool']['bonded_tokens']})")
        
        # Check 2: Each of the validators in the comet validator set must be bonded
        comet_validator_issues = []
        for pubkey in self.data['comet_validator_set'].keys():
            operator_address = None
            for val in self.data['validator_info']:
                if val['pubkey'] == pubkey:
                    operator_address = val['operator_address']
                    break
            if operator_address is None:
                issue = f"❌ MISSING VALIDATOR: Pubkey {pubkey} in comet set not found in validator info"
                comet_validator_issues.append(issue)
                logging.warning(f"❌ Validator with pubkey {pubkey} in comet validator set not found in validator info")
                continue
            
            val_info = None
            for val in self.data['validator_info']:
                if val['operator_address'] == operator_address:
                    val_info = val
                    break
            if val_info is None:
                continue
            if val_info['bonded'] == 'BOND_STATUS_BONDED':
                continue
            else:
                issue = f"❌ UNBONDED VALIDATOR: {operator_address} (status={val_info['bonded']})"
                comet_validator_issues.append(issue)
                logging.warning(f"❌ Validator {operator_address} with pubkey {pubkey} is not bonded")

        # Check 3: The tokens vp fraction must equal the comet vp fraction for each validator
        vp_fraction_issues = []
        for pubkey in self.data['comet_validator_set'].keys():
            operator_address = None
            for val in self.data['validator_info']:
                if val['pubkey'] == pubkey:
                    operator_address = val['operator_address']
                    break
            if operator_address is None:
                continue
            val_info = None
            for val in self.data['validator_info']:
                if val['operator_address'] == operator_address:
                    val_info = val
                    break
            if val_info is None:
                continue
            if abs(val_info['tokens_vp_fraction'] - val_info['comet_vp_fraction']) < 1e-6:
                continue
            else:
                issue = f"❌ VOTING POWER MISMATCH: {operator_address} tokens={val_info['tokens_vp_fraction']:.6f} comet={val_info['comet_vp_fraction']:.6f}"
                vp_fraction_issues.append(issue)
                logging.warning(f"❌ Validator {operator_address} with pubkey {pubkey} has different voting power fraction in tokens ({val_info['tokens_vp_fraction']:.6f}) and comet ({val_info['comet_vp_fraction']:.6f})")
        
        # Write report to text file
        with open(self.check_prefix + '-' + str(self.height) + '.txt', 'w') as f:
            f.write("VALIDATOR SET CHECK REPORT\n")
            f.write("=" * 30 + "\n")
            f.write(f"Height: {self.height if self.height > 0 else 'latest'}\n\n")
            
            # Bonded tokens check
            if not issues:
                f.write("✅ Total bonded tokens from validator info matches staking pool.\n")
            else:
                f.write("BONDED TOKENS ISSUES:\n")
                for issue in issues:
                    f.write(f"  {issue}\n")
                f.write("\n")
            
            # Comet validator set checks
            if not comet_validator_issues:
                f.write("✅ All validators in the comet set are bonded.\n")
            else:
                f.write("COMET VALIDATOR SET ISSUES:\n")
                for issue in comet_validator_issues:
                    f.write(f"  {issue}\n")
                f.write("\n")
            
            # Voting power fraction checks
            if not vp_fraction_issues:
                f.write("✅ All validators have a matching voting power fraction for comet and tokens.\n")
            else:
                f.write("VOTING POWER FRACTION ISSUES:\n")
                for issue in vp_fraction_issues:
                    f.write(f"  {issue}\n")
        
        logging.info(f"Validation report written to {self.check_prefix + '-' + str(self.height) + '.txt'}")
            

    def collect(self):
        # 0. Get block height if not provided
        if self.height == 0:
            self.height = rpc_get_current_height(self.urlRPC)
            self.data['height'] = self.height   
        # 1. Params and staking pool
        self.get_provider_params()
        self.get_staking_params()
        self.get_staking_pool()
        # 2. Comet validator set
        self.get_comet_validator_set()
        # 3. Validator info
        self.get_validator_info()
        # 4. Self check
        # self.self_check()


class ValsetCheck():
    def __init__(self,
                urlAPI: str='http://localhost:25001',
                urlRPC: str='http://localhost:27001',
                binary: str='gaiad',
                height: int=0,
                ics_removal_upgrade: bool=False,
                provider_max_vals: int=0,
                output_prefix: str='valset-compare'):
        
        self.urlAPI = urlAPI
        self.urlRPC = urlRPC
        self.binary = binary
        self.height = height
        self.provider_max_vals = provider_max_vals
        self.output_prefix = output_prefix
        self.data = {'checks': {}, 'operations': []}
        self.ics_disable_upgrade = ics_removal_upgrade


    def get_events_from_transaction(self, tx:dict):
        """
        Get the events from a transaction and check if there are any staking messages.
        If there are, store them in self.data['operations'] to be used in the checks later.
        """
        tx_events = tx.get('events', [])

        for event in tx_events:
            operation = {
                'operation': None,
                'amount': None
            }
            if event['type'] == 'delegate':
                operation['operation'] = 'delegate'
                for attribute in event['attributes']:
                    if attribute['key'] == 'amount':
                            operation['amount'] = int(attribute['value'].strip('uatom'))
                    if attribute['key'] == 'validator':
                            operation['validator'] = attribute['value']
            if event['type'] == 'unbond':
                operation['operation'] = 'unbond'
                for attribute in event['attributes']:
                    if attribute['key'] == 'amount':
                            operation['amount'] = int(attribute['value'].strip('uatom'))
                    if attribute['key'] == 'validator':
                            operation['validator'] = attribute['value']
            if event['type'] == 'redelegate':
                operation['operation'] = 'redelegate'
                for attribute in event['attributes']:
                    if attribute['key'] == 'amount':
                            operation['amount'] = int(attribute['value'].strip('uatom'))
                    if attribute['key'] == 'source_validator':
                            operation['source_validator'] = attribute['value']
                    if attribute['key'] == 'destination_validator':
                            operation['destination_validator'] = attribute['value']
            if operation['operation']:
                self.data['operations'].append(operation)
            
    def get_staking_messages(self):
        """
        Get all the staking messages in block N and store them in self.data['operations'].
        This will be used to check that the changes in the validator set are correct based on the rotations applied.
        """
        try:
            block_results = rpc_get_block_results(self.urlRPC, self.height)
            txs_results = block_results.get('txs_results', [])
            for tx in txs_results:
                if 'events' in tx:
                    self.get_events_from_transaction(tx)
        except Exception as e:
            logging.error(f"Failed to fetch staking messages for block {self.height}: {e}")
            self.data['operations'] = []


    def collect_inputs(self):
        """
        Collect data for starting height and ending height (after rotations)
        """
        
        valset_info_n_minus_2 = ValsetInfo(urlAPI=self.urlAPI, urlRPC=self.urlRPC, binary=self.binary, height=self.height-2)
        valset_info_n_minus_1 = ValsetInfo(urlAPI=self.urlAPI, urlRPC=self.urlRPC, binary=self.binary, height=self.height-1)
        valset_info_n = ValsetInfo(urlAPI=self.urlAPI, urlRPC=self.urlRPC, binary=self.binary, height=self.height)
        valset_info_n_plus_1 = ValsetInfo(urlAPI=self.urlAPI, urlRPC=self.urlRPC, binary=self.binary, height=self.height+1)
        valset_info_n_plus_2 = ValsetInfo(urlAPI=self.urlAPI, urlRPC=self.urlRPC, binary=self.binary, height=self.height+2)
        valset_info_n_plus_3 = ValsetInfo(urlAPI=self.urlAPI, urlRPC=self.urlRPC, binary=self.binary, height=self.height+3)
        
        valset_info_n_minus_2.collect()
        valset_info_n_minus_1.collect()
        valset_info_n.collect()
        valset_info_n_plus_1.collect()
        valset_info_n_plus_2.collect()
        valset_info_n_plus_3.collect()
        self.data['n-2'] = valset_info_n_minus_2.data
        self.data['n-1'] = valset_info_n_minus_1.data
        self.data['n'] = valset_info_n.data
        self.data['n+1'] = valset_info_n_plus_1.data
        self.data['n+2'] = valset_info_n_plus_2.data
        self.data['n+3'] = valset_info_n_plus_3.data

        # Get staking messages from block N
        self.get_staking_messages()

    def apply_expected_bonded_status(self):
        """
        Apply the expected bonded status based on the reordering of the validators due to token changes.
        """
        for validator in self.data['n']['expected_validator_info']:

            # # Get comet rank for validator in n-1
            # for old_val in self.data['n-1']['validator_info']:
            #     if old_val['operator_address'] == validator['operator_address']:
            #         old_rank = old_val.get('comet_rank', None)
            # #         break
            
            if validator['jailed']:
                logging.info(f'Skipping validator {validator["moniker"]} in bonded status check because it is jailed in block n with {validator["tokens"]} tokens')
                continue
            
            validator['comet_rank'] = self.data['n']['rank_change_validators'][validator['operator_address']]['ending_rank']
            if not self.data['n']['rank_change_validators'][validator['operator_address']]['rank_change']:
                logging.info(f'Validator {validator["moniker"]} with {validator["tokens"]} tokens and comet rank {validator["comet_rank"]} did not change rank.')               
            else:
                validator['comet_rank'] = self.data['n']['rank_change_validators'][validator['operator_address']]['ending_rank']
                # 1. Is it within the max_validators threshold?
                if validator['comet_rank'] <= self.data['n']['staking_validators']:
                    if validator['bonded'] == 'BOND_STATUS_UNBONDED' or validator['bonded'] == 'BOND_STATUS_UNBONDING':
                        validator['bonded'] = 'BOND_STATUS_BONDED'
                # 2. Is if outside the max_validators threshold?
                if validator['comet_rank'] > self.data['n']['staking_validators'] and validator['bonded'] == 'BOND_STATUS_BONDED':
                    validator['bonded'] = 'BOND_STATUS_UNBONDING'
            logging.info(f"Validator {validator['moniker']} is expected to have status {validator['bonded']} tokens after applying operations because it is ranked {validator['comet_rank']}")
            # if validator['bonded'] == 'BOND_STATUS_UNBONDED' or validator['bonded'] == 'BOND_STATUS_UNBONDING' and (old_rank and old_rank > self.data['n-1']['staking_validators']):
                # if validator['comet_rank'] <= self.data['n']['staking_validators']:
                    # validator['bonded'] = 'BOND_STATUS_BONDED'
                    # logging.info(f"Validator {validator['moniker']} is expected to be bonded with {validator['tokens']} tokens after applying operations because it was ranked {old_rank} in block n-1 which is above the max validators limit of {self.data['n-1']['staking_validators']} but is ranked {validator['comet_rank']} in block n which is below the max validators limit of {self.data['n']['staking_validators']}")
            # if self.ics_disable_upgrade and validator['comet_rank'] > self.provider_max_vals:
                # if validator['bonded'] == 'BOND_STATUS_BONDED':
                    # validator['bonded'] = 'BOND_STATUS_UNBONDING'
                    # logging.info(f"Validator {validator['moniker']} is expected to be unbonding with {validator['tokens']} tokens after applying operations because ICS is disabled and it is ranked {validator['comet_rank']} which is above the provider max validators limit of {self.provider_max_vals}")
            # if new_rank > self.provider_max_vals:
                # break
        # for i in range(self.data['n']['staking_validators']):
            # validator = self.data['n']['expected_validator_info'][i]
            # print(validator['moniker'], validator['tokens'], validator['comet_rank'], validator['bonded'])
            # if validator['bonded'] == 'BOND_STATUS_BONDED':
                # logging.info(f"Validator {validator['moniker']} is expected to be {validator['bonded']} with {validator['tokens']} tokens after applying operations")


    def calculate_expected_total_bonded_tokens(self):
        """
        Calculate the expected total bonded tokens based on the rotations applied.
        This will be used to check that the total bonded tokens in block N+1 matches the expected total bonded tokens after the rotations are applied.
        """
        total_bonded_tokens = 0
        for val in self.data['n']['expected_validator_info']:
            if val['bonded'] == 'BOND_STATUS_BONDED':
                total_bonded_tokens += val['tokens']
        self.data['n']['expected_total_bonded_tokens'] = total_bonded_tokens

    def calculate_expected_validator_data(self):
        """
        Calculate the expected validator set based on the rotations applied and the max_validators param if ICS is disabled.
        This will be used to check that the actual validator set in block N+1 matches the expected validator set.
        """
        self.data['n']['expected_validator_info'] = copy.deepcopy(self.data['n-1']['validator_info'])
        
        rank_comparison = {}
        for val in self.data['n']['expected_validator_info']:
            rank_comparison[val['operator_address']] = {
                'moniker': val['moniker'],
                'starting_vp': int(val['tokens']/1000000), # Convert from uatom to atom for voting power calculation
                'rank_change': False
            }
        # Assign a "starting_rank" field to each validator in rank_comparison based on their starting_vp
        sorted_validators = sorted(rank_comparison.items(), key=lambda x: x[1]['starting_vp'], reverse=True)
        for rank, (operator_address, val) in enumerate(sorted_validators, start=1):
            rank_comparison[operator_address]['starting_rank'] = rank
        
        # Iterate through each operation to apply the changes to the tokens for each validator
        for op in self.data['operations']:
            for new_val in self.data['n']['expected_validator_info']:
                if op['operation'] == 'redelegate':
                    if new_val['operator_address'] == op['source_validator']:
                        new_val['tokens'] -= int(op['amount'])
                        logging.info(f"Applying redelegate operation: {op['amount']} tokens moved from {op['source_validator']} to {op['destination_validator']}")
                    if new_val['operator_address'] == op['destination_validator']:
                        new_val['tokens'] += int(op['amount'])
                        logging.info(f"Applying redelegate operation: {op['amount']} tokens moved from {op['source_validator']} to {op['destination_validator']}")
                elif op['operation'] == 'delegate':
                    if new_val['operator_address'] == op['validator']:
                        new_val['tokens'] += int(op['amount']) 
                        logging.info(f"Applying delegate operation: {op['amount']} tokens delegated to {op['validator']}")
                elif op['operation'] == 'unbond':
                    if new_val['operator_address'] == op['validator']:
                        new_val['tokens'] -= int(op['amount'])
                        logging.info(f"Applying unbond operation: {op['amount']} tokens unbonded from {op['validator']}")
       
        for val in self.data['n']['expected_validator_info']:
            rank_comparison[val['operator_address']]['ending_vp'] = int(val['tokens']/1000000)
        
        sorted_validators = sorted(rank_comparison.items(), key=lambda x: x[1]['ending_vp'], reverse=True)
        for rank, (operator_address, val) in enumerate(sorted_validators, start=1):
            rank_comparison[operator_address]['ending_rank'] = rank
        # Check which validators are expected to be bonded or unbonded based on their new rank in the validator set (preop vs expected validator info)
        for op in rank_comparison.keys():
            if rank_comparison[op]['starting_rank'] != rank_comparison[op]['ending_rank']:
                rank_comparison[op]['rank_change'] = True

        # Create list of validators with rank changes
        # print(f'rank_change_validators: {rank_comparison}')
        self.data['n']['rank_change_validators'] = rank_comparison
        
        self.apply_expected_bonded_status()

        self.calculate_expected_total_bonded_tokens()
        # self.print_bonded_tokens()

    def print_bonded_tokens(self):
        """
        Print the list of validator monikers and their bonded tokens for block N-1, bonded tokens for block N,
        and the expected bonded tokens after the staking operations are applied.
        """
        bonded_data = {}
        # 1. Get list of validators from block N-1 and their bonded tokens
        for val in self.data['n-1']['validator_info']:
            if val['bonded'] != 'BOND_STATUS_BONDED':
               bonded_data[val['operator_address']] = {
                'moniker': val['moniker'],
                'n-1': 0
                }
               continue
            # logging.info(f"Block N-1: Validator {val['moniker']} has {val['tokens']} bonded tokens")
            bonded_data[val['operator_address']] = {
                'moniker': val['moniker'],
                'n-1': val['tokens']
            }
        # 2. Get tokens for the same validators in block N
        for val in self.data['n']['validator_info']:
            if val['operator_address'] in bonded_data:
                if val['bonded'] != 'BOND_STATUS_BONDED':
                    bonded_data[val['operator_address']]['n'] = 0
                    continue
                # logging.info(f"Block N: Validator {val['moniker']} has {val['tokens']} bonded tokens")
                bonded_data[val['operator_address']]['n'] = val['tokens']
        # 3. Get expected tokens for the same validators after applying the operations
        for val in self.data['n']['expected_validator_info']:
            if val['operator_address'] in bonded_data:
                if val['bonded'] != 'BOND_STATUS_BONDED':
                    bonded_data[val['operator_address']]['expected'] = 0
                    continue
                # logging.info(f"Expected after operations: Validator {val['moniker']} has {val['tokens']} bonded tokens")
                bonded_data[val['operator_address']]['expected'] = val['tokens']
        # Print bonded_data in tabulated format
        logging.info(f"{'Validator':<20} {'N-1 Tokens':<15} {'N Tokens':<15} {'Expected Tokens':<15}")
        for op_addr, data in bonded_data.items():
            logging.info(f"{data['moniker']:<20} {data.get('n-1', 'N/A'):<15} {data.get('n', 'N/A'):<15} {data.get('expected', 'N/A'):<15}")

    def calculate_expected_comet_validator_sets(self):
        """
        Calculate the expected comet validator set based on the expected bonded status and the tokens for each validator.
        """
        
        expected_comet_set = {}
        index = 0

        for val in self.data['n-2']['validator_info']:
            if val['bonded'] == 'BOND_STATUS_BONDED':
                index += 1
                if index > self.provider_max_vals:
                    break
                # print(f'validator: {val["moniker"]}, tokens: {val["tokens"]}, voting power: {int(val["tokens"]/1000000)}')
                expected_comet_set[val['pubkey']] = {
                    'voting_power': int(val['tokens']/1000000), # Convert from uatom to atom for voting power calculation
                }
                
        # print(f'Expected_comet_set size: {len(expected_comet_set)}')
        # Sort comet set by voting power
        expected_comet_set = dict(sorted(expected_comet_set.items(), key=lambda item: item[1]['voting_power'], reverse=True))
        for index, (_, val) in enumerate(expected_comet_set.items(), start=1):
            val['rank'] = index
        self.data['n']['expected_comet_validator_set'] = expected_comet_set
        # logging.info(f"Expected comet validator set size calculated based on block n-2 validator info: {len(expected_comet_set)} validators")


        expected_comet_set = {}
        for val in self.data['n']['expected_validator_info']:
            if val['bonded'] == 'BOND_STATUS_BONDED':
                if val['comet_rank'] > self.provider_max_vals:
                    break
                expected_comet_set[val['pubkey']] = {
                    'voting_power': int(val['tokens']/1000000), # Convert from uatom to atom for voting power calculation
                }
        # Sort comet set by voting power
        expected_comet_set = dict(sorted(expected_comet_set.items(), key=lambda item: item[1]['voting_power'], reverse=True))
        for index, (_, val) in enumerate(expected_comet_set.items(), start=1):
            val['rank'] = index
        self.data['n+2']['expected_comet_validator_set'] = expected_comet_set


    def ics_param_check(self):
        """
        [n+1]
        Only runs if ICS is enabled at height N and disabled at height N+1.
        Checks if the the max_validators staking param at the ending height matches
        the max_provider_consensus_validators param at the starting height.
        """
        if self.data['n']['staking_validators'] is None:
            logging.error("Cannot perform ICS param check because max_validators param could not be fetched at the upgrade height")
            self.data['checks']['ics_param_check'] = 'FAIL'
            return
        if self.provider_max_vals != self.data['n']['staking_validators']:
            self.data['checks']['ics_param_check'] = 'FAIL'
            logging.error(f"> ICS param check failed: max_provider_consensus_validators at block n is {self.provider_max_vals} but max_validators at block n+1 is {self.data['n+1']['staking_validators']}")
            exit()
        else:
            logging.info("> ICS param check passed: max_provider_consensus_validators at block n matches max_validators at block n")
            self.data['checks']['ics_param_check'] = 'PASS'

    def comet_size_param_check(self):
        """
        If ICS is disabled:
        Checks that the comet validator set size matches whichever is lower between:
            * The staking module max_validators parameter, or
            * The number of bonded validators at block N-2
        If ICS is enabled:
        Checks that the comet validator set size matches whichever is lower:
            * The provider module max_provider_consensus_validators parameter, or
            * The number of bonded validators at block N-2
        """
        comet_size = len(self.data['n']['comet_validator_set'])
        if not self.ics_disable_upgrade:
            expected_size = len(self.data['n']['expected_comet_validator_set'])
            if expected_size is None:
                logging.error("Cannot perform comet size check because provider params could not be fetched at the starting height")
                self.data['checks']['comet_size_check'] = 'FAIL'
                return
            if comet_size != expected_size:
                logging.error(f"> Comet validator set size check failed with ICS enabled: expected {expected_size} but got {comet_size}")
                self.data['checks']['comet_size_check'] = 'FAIL'
            else:
                logging.info(f"> Comet validator set size check passed with ICS enabled: expected {expected_size} matches actual {comet_size}")
                self.data['checks']['comet_size_check'] = 'PASS'
        else:
            expected_size = len(self.data['n']['expected_comet_validator_set'])
            if expected_size is None:
                logging.error("> Cannot perform comet size check because max_validators param could not be fetched at the ending height")
                self.data['checks']['comet_size_check'] = 'FAIL'
                return
            if comet_size != expected_size:
                logging.error(f"> Comet validator set size check failed with ICS disabled: expected {expected_size} but got {comet_size}")
                self.data['checks']['comet_size_check'] = 'FAIL'
            else:
                logging.info(f"> Comet validator set size check passed with ICS disabled: expected {expected_size} matches actual {comet_size}")
                self.data['checks']['comet_size_check'] = 'PASS'

    def total_bonded_tokens_check(self):
        """
        Check that the staking pool values are correct based on the transactions collected.
        """
        if self.data['n']['expected_total_bonded_tokens'] != self.data['n']['total_bonded_tokens']:
            logging.error(f"> Total bonded tokens check failed: expected {self.data['n']['expected_total_bonded_tokens']} but got {self.data['n']['total_bonded_tokens']}")
            self.data['checks']['total_bonded_tokens'] = 'FAIL'
        else:
            logging.info(f"> Total bonded tokens check passed: expected {self.data['n']['expected_total_bonded_tokens']} matches actual {self.data['n']['total_bonded_tokens']}")
            self.data['checks']['total_bonded_tokens'] = 'PASS'
        
    def staking_pool_bonded_tokens_check(self):
        """
        The staking pool bonded tokens should match the calculated total bonded tokens.
        """
        if self.data['n']['expected_total_bonded_tokens'] != self.data['n']['staking_pool']['bonded_tokens']:
            logging.error(f"> Staking pool bonded tokens check failed: expected {self.data['n']['expected_total_bonded_tokens']} but got {self.data['n']['staking_pool']['bonded_tokens']}")
            self.data['checks']['staking_pool_bonded_tokens'] = 'FAIL'
        else:
            logging.info(f"> Staking pool bonded tokens check passed, expected {self.data['n']['expected_total_bonded_tokens']} matches actual {self.data['n']['staking_pool']['bonded_tokens']}")
            self.data['checks']['staking_pool_bonded_tokens'] = 'PASS'

    def comet_size_bonded_validators_check(self):
        """
        If ICS is disabled:
        Checks that the comet validator set size matches the number of validators with `BOND_STATUS_BONDED` status.
        """
        comet_size = len(self.data['n']['comet_validator_set'])
        if self.ics_disable_upgrade:
            bonded_validators = 0
            for val in self.data['n']['validator_info']:
                if val['bonded'] == 'BOND_STATUS_BONDED':
                    bonded_validators += 1
            if comet_size != bonded_validators:
                logging.error(f"> Comet validator set size check failed with ICS disabled: expected {bonded_validators} bonded validators but got comet validator set size of {comet_size}")
                self.data['checks']['comet_size_bonded_validators_check'] = 'FAIL'
            else:
                logging.info(f"> Comet validator set size check passed with ICS disabled: expected {bonded_validators} bonded validators matches comet validator set size of {comet_size}")
                self.data['checks']['comet_size_bonded_validators_check'] = 'PASS'

    def validator_tokens_check(self):
        """
        Check that the bonded tokens for each validator are correct based on the transactions applied.
        """
        for val in self.data['n']['expected_validator_info']:
            expected_tokens = val['tokens']
            for ref_val in self.data['n']['validator_info']:
                if ref_val['operator_address'] == val['operator_address']:
                    actual_tokens = ref_val['tokens']
                    break
            if expected_tokens != actual_tokens:
                logging.error(f"> Validator tokens check failed for {val['operator_address']}: expected {expected_tokens} but got {actual_tokens}")
                self.data['checks'][f"validator_tokens_{val['operator_address']}"] = 'FAIL'
            else:
                logging.info(f"> Validator tokens check passed for {val['operator_address']}: expected {expected_tokens} matches actual {actual_tokens}")
                self.data['checks'][f"validator_tokens_{val['operator_address']}"] = 'PASS'

    def validator_status_check(self):
        """
        Check that the validator status is correct based on the transactions applied.
        """
        for val in self.data['n']['expected_validator_info']:
            expected_status = val['bonded']
            for ref_val in self.data['n']['validator_info']:
                if ref_val['operator_address'] == val['operator_address']:
                    actual_status = ref_val['bonded']
                    break
            if expected_status != actual_status:
                logging.error(f"> Validator status check failed for {val['operator_address']}: expected {expected_status} but got {actual_status}")
                self.data['checks'][f"validator_status_{val['operator_address']}"] = 'FAIL'
            else:
                logging.info(f"> Validator status check passed for {val['operator_address']}: expected {expected_status} matches actual {actual_status}")
                self.data['checks'][f"validator_status_{val['operator_address']}"] = 'PASS'
                
    def comet_validator_set_pre_check(self):
        """
        Checks that the actual validator set matches the expected one at N.
        """
        for pubkey, data in self.data['n']['expected_comet_validator_set'].items():
            if pubkey not in self.data['n']['comet_validator_set']:
                logging.error(f"> Comet validator set pre-check failed for pubkey {pubkey}: expected to be in comet validator set but was not found")
                self.data['checks'][f"comet_precheck_{pubkey}"] = 'FAIL'
            else:
                logging.info(f"> Comet validator set pre-check passed for pubkey {pubkey}: expected to be in comet validator set and was found")
                self.data['checks'][f"comet_precheck_{pubkey}"] = 'PASS'
                if data['voting_power'] is not None:
                    expected_vp = data['voting_power']
                    actual_vp = self.data['n']['comet_validator_set'][pubkey]['voting_power']
                    if expected_vp != actual_vp:
                        logging.error(f"> Comet validator set pre-check failed for pubkey {pubkey}: expected voting power {expected_vp} but got {actual_vp}")
                        self.data['checks'][f"comet_precheck_vp_{pubkey}"] = 'FAIL'
                    else:
                        logging.info(f"> Comet validator set pre-check passed for pubkey {pubkey}: expected voting power {expected_vp} matches actual {actual_vp}")
                        self.data['checks'][f"comet_precheck_vp_{pubkey}"] = 'PASS'


    def comet_validator_set_post_check(self):
        """
        Checks that the actual validator set matches the expected one at N+2.
        """
        for pubkey, data in self.data['n+2']['expected_comet_validator_set'].items():
            if pubkey not in self.data['n+2']['comet_validator_set']:
                logging.error(f"> Comet validator set post-check failed for pubkey {pubkey}: expected to be in comet validator set but was not found")
                self.data['checks'][f"comet_postcheck_{pubkey}"] = 'FAIL'
            else:
                logging.info(f"> Comet validator set post-check passed for pubkey {pubkey}: expected to be in comet validator set and was found")
                self.data['checks'][f"comet_postcheck_{pubkey}"] = 'PASS'
                if data['voting_power'] is not None:
                    expected_vp = data['voting_power']
                    actual_vp = self.data['n+2']['comet_validator_set'][pubkey]['voting_power']
                    if expected_vp != actual_vp:
                        logging.error(f"> Comet validator set post-check failed for pubkey {pubkey}: expected voting power {expected_vp} but got {actual_vp}")
                        self.data['checks'][f"comet_postcheck_vp_{pubkey}"] = 'FAIL'
                    else:
                        logging.info(f"> Comet validator set post-check passed for pubkey {pubkey}: expected voting power {expected_vp} matches actual {actual_vp}")
                        self.data['checks'][f"comet_postcheck_vp_{pubkey}"] = 'PASS'


    def voting_power_pre_check(self):
        """
        [N-2]: Bonded tokens VP
        [N]: Comet validator set VP
        Checks that the voting power for each validator in the comet validator set in block N matches their bonded tokens based voting power in block N-2.
        """
        comet_set = self.data['n']['comet_validator_set']
        for val in self.data['n-2']['validator_info']:
            if val['pubkey'] in comet_set:
                expected_vp = int(val['tokens']/1000000)
                actual_vp = comet_set[val['pubkey']]['voting_power']
                if expected_vp != actual_vp:
                    logging.error(f"> Validator voting power pre-check failed for {val['operator_address']}: expected {expected_vp} but got {actual_vp}")
                    self.data['checks'][f"voting_power_precheck_{val['operator_address']}"] = 'FAIL'
                else:
                    logging.info(f"> Validator voting power pre-check passed for {val['operator_address']}: expected {expected_vp} matches actual {actual_vp}")
                    self.data['checks'][f"voting_power_precheck_{val['operator_address']}"] = 'PASS'
        
    def voting_power_post_check(self):
        """
        [N]: Bonded tokens VP
        [N+2]: Comet validator set VP
        Checks that the voting power for each validator in the comet validator set in block N+2 matches their bonded tokens based voting power in block N.
        """
        comet_set = self.data['n+2']['comet_validator_set']
        for val in self.data['n']['validator_info']:
            if val['pubkey'] in comet_set:
                expected_vp = int(val['tokens']/1000000)
                actual_vp = comet_set[val['pubkey']]['voting_power']
                if expected_vp != actual_vp:
                    logging.error(f"> Validator voting power post-check failed for {val['operator_address']}: expected {expected_vp} but got {actual_vp}")
                    self.data['checks'][f"voting_power_postcheck_{val['operator_address']}"] = 'FAIL'
                else:
                    logging.info(f"> Validator voting power post-check passed for {val['operator_address']}: expected {expected_vp} matches actual {actual_vp}")
                    self.data['checks'][f"voting_power_postcheck_{val['operator_address']}"] = 'PASS'
        

    def check(self):
        """
        Check each of the fields and verify that the changes are correct based on the rotations that were applied
        """
        # 1. ICS param check
        if self.ics_disable_upgrade:
            logging.info("> ICS param migration check")
            self.ics_param_check()
        # 2. Param value must match comet validator set size
        logging.info("> Comet validator set size check")
        self.comet_size_param_check()
        
        # 3. Total bonded tokens check
        logging.info("> Total bonded tokens check")
        self.total_bonded_tokens_check()

        # 4. Staking pool check
        logging.info("> Staking pool bonded tokens check")
        self.staking_pool_bonded_tokens_check()

        # 5. Number of bonded validators must match comet validator set size if ICS is disabled
        logging.info("> Comet validator set size vs bonded validators check")
        self.comet_size_bonded_validators_check()

        # 6. Validator set changes: Tokens
        logging.info("> Validator tokens check")
        self.validator_tokens_check()

        # 7. Validator set changes: Status (active/inactive based on max validators and bonded status)
        logging.info("> Validator status check")
        self.validator_status_check()

        # 8. Comet validator set
        logging.info("> Comet validator set check")
        self.comet_validator_set_pre_check()
        self.comet_validator_set_post_check()


        # print(json.dumps(self.data['checks'], indent=4))

    def save(self):
        logging.info(f'Saving to {self.output_prefix + "-" + str(self.height) + ".json"}')
        with open(self.output_prefix + '-' + str(self.height) + '.json', 'w') as f:
            json.dump(self.data, f, indent=4)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Get validator set information')
    parser.add_argument('--api', type=str, default='http://localhost:25001', 
                        help='API endpoint URL (default: http://localhost:25001)')
    parser.add_argument('--rpc', type=str, default='http://localhost:27001',
                        help='RPC endpoint URL (default: http://localhost:27001)')
    parser.add_argument('--binary', type=str, default='gaiad',
                        help='Binary name (default: gaiad)')
    parser.add_argument('--height', type=int, required=True,
                        help='Block height to query (default: 0 for latest)')
    parser.add_argument('--ics-removal-upgrade', action='store_true',
                        help='Flag to indicate if the upgrade being analyzed is the ICS removal upgrade (default: False)')
    parser.add_argument('--provider-max-vals', type=int, default=0,
                        help='Max provider consensus validators param value (default: 0, required if --ics-removal-upgrade is set)')
    parser.add_argument('--output', type=str, default='validator-check',
                        help='Output file name prefix (default: validator-check-<height>.json)')
    
    args = parser.parse_args()
    
    vc = ValsetCheck(urlAPI=args.api, urlRPC=args.rpc, binary=args.binary, height=args.height, ics_removal_upgrade=args.ics_removal_upgrade, provider_max_vals=args.provider_max_vals, output_prefix=args.output)
    vc.collect_inputs()
    vc.calculate_expected_validator_data()
    # exit()
    vc.calculate_expected_comet_validator_sets()
    vc.check()
    vc.save()