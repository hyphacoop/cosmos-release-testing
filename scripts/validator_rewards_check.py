"""
Validator Rewards Check
Adds up the validator rewards for each validator and outputs the total for each denom found
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


def api_get_supply_of(urlAPI: str, denom: str, height: int = 0):
    """
    Returns the total supply for a specific denom.
    Endpoint: GET /cosmos/bank/v1beta1/supply/by_denom?denom={denom}
    Response: {'amount': {'denom': str, 'amount': str}}
    Note: this endpoint returns a single coin, so no pagination is needed.
    """
    endpoint = f"{urlAPI}/cosmos/bank/v1beta1/supply/by_denom?denom={urllib.parse.quote(denom)}"
    if height:
        response = requests.get(
            endpoint, headers={"x-cosmos-block-height": f"{height}"}
        ).json()
    else:
        response = requests.get(endpoint).json()
    if "amount" in response:
        return response["amount"]['amount']
    return {}

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


class RewardsInfo():
    def __init__(self,
                urlAPI: str='http://localhost:25001',
                urlRPC: str='http://localhost:27001',
                binary: str='gaiad',
                height: int=0,
                output_prefix: str='rewards-info'):
        
        self.urlAPI = urlAPI
        self.urlRPC = urlRPC
        self.binary = binary
        self.height = height
        self.output_prefix = output_prefix
        self.operators = set()
        self.data = {
            'height': self.height,
            'balances': {},
            'consumer_rewards_denoms': [],
            'consumer_rewards_pool': {}
        }

        self.CONSUMER_REWARDS_POOL_ADDRESS = 'cosmos1ap0mh6xzfn8943urr84q6ae7zfnar48am2erhd'
    # def get_operators(self):
    #     val_list = api_get_validators(self.urlAPI, height=self.height)
    #     for val in val_list:
    #         operator = val['operator_address']
    #         self.operators.add(operator)

    # def get_rewards(self):
    #     for operator in self.operators:
    #         print(f'> Fetching rewards for validator {operator} at height {self.height}.')
    #         response = requests.get(f"{self.urlAPI}/cosmos/distribution/v1beta1/validators/{operator}/outstanding_rewards?height={self.height}").json()
    #         if 'code' in response and response['code'] != 0:
    #             logging.error(f"Error fetching rewards for validator {operator}: {response['message']}")
    #             continue
    #         rewards = response['rewards']['rewards']
    #         self.data['validators'][operator] = rewards


    def get_consumer_rewards_denoms(self):
        response = requests.get(f"{self.urlAPI}/cosmos/bank/v1beta1/balances/{self.CONSUMER_REWARDS_POOL_ADDRESS}?height={self.height}").json()
        if 'code' in response and response['code'] != 0:
            logging.error(f"Error fetching community pool: {response['message']}")
            return
        pool = response['balances']
        denoms = set()
        for coin in pool:
            denoms.add(coin['denom'])
            self.data['consumer_rewards_pool'][coin['denom']] = coin['amount']
        self.data['consumer_rewards_denoms'] = list(denoms)

    def get_supplies(self):
        for denom in self.data['consumer_rewards_denoms']:
            supply = api_get_supply_of(self.urlAPI, denom, height=self.height)
            self.data['balances'][denom] = supply

    def collect(self):
        # 0. Get block height if not provided
        if self.height == 0:
            self.height = rpc_get_current_height(self.urlRPC)
            self.data['height'] = self.height   
        
        self.get_consumer_rewards_denoms()
        self.get_supplies()

        with open(f'{self.output_prefix}-{self.height}.json', 'w') as f:
            json.dump(self.data, f, indent=4)


class RewardsCheck():
    def __init__(self,
                urlAPI: str='http://localhost:25001',
                urlRPC: str='http://localhost:27001',
                binary: str='gaiad',
                height: int=0,
                ics_removal_upgrade: bool=False,
                output_prefix: str='rewards-check'):
        
        self.urlAPI = urlAPI
        self.urlRPC = urlRPC
        self.binary = binary
        self.height = height
        self.output_prefix = output_prefix
        self.data = {'checks': {}, 'operations': []}
        self.ics_disable_upgrade = ics_removal_upgrade


    def collect_inputs(self):
        """
        Collect data for starting height and ending height (after rotations)
        """
        if not self.height:
            # Get current height
            self.height = rpc_get_current_height(self.urlRPC)
        logging.info(f"Collecting inputs.")

        rewards_info_n_minus_1 = RewardsInfo(urlAPI=self.urlAPI, urlRPC=self.urlRPC, binary=self.binary, height=self.height-1)
        rewards_info_n = RewardsInfo(urlAPI=self.urlAPI, urlRPC=self.urlRPC, binary=self.binary, height=self.height)
        
        rewards_info_n_minus_1.collect()
        rewards_info_n.collect()
        self.data['n-1'] = rewards_info_n_minus_1.data
        self.data['n'] = rewards_info_n.data
        

    def check_balances(self):
        """
        Check that the balances for the consumer rewards denoms are correct based on the rewards distribution and the supplies.
        """
        if self.ics_disable_upgrade:
            # The balance for each of the denom in the balances field should decrease by the amount in the consumer rewards pool, since all the rewards are distributed to the consumer rewards pool and there are no more validator rewards.
            for denom in self.data['n']['consumer_rewards_denoms']:
                if denom == 'uatom':
                    # Skip checking uatom balance since there is also the mint module that mints new uatoms which can interfere with the balance check.
                    continue
                balance_n_minus_1 = int(self.data['n-1']['balances'][denom])
                balance_n = int(self.data['n']['balances'][denom])
                rewards_pool_amount = int(self.data['n']['consumer_rewards_pool'][denom])
                expected_balance_n = balance_n_minus_1 - rewards_pool_amount
                if balance_n != expected_balance_n:
                    logging.error(f"Balance for denom {denom} is incorrect. Expected {expected_balance_n}, got {balance_n}.")
                    self.data['checks'][denom] = {
                        'status': 'FAIL',
                        'expected_balance': expected_balance_n,
                        'actual_balance': balance_n
                    }
                else:
                    logging.info(f"Balance for denom {denom} is correct.")
                    self.data['checks'][denom] = {
                        'status': 'PASS',
                        'expected_balance': expected_balance_n,
                        'actual_balance': balance_n
                    }
        else:
            # The balance for each of the denom in the balances field should remain the same since the rewards distribution should not be affected.
            for denom in self.data['n']['consumer_rewards_denoms']:
                if denom == 'uatom':
                    # Skip checking uatom balance since there is also the mint module that mints new uatoms which can interfere with the balance check.
                    continue
                balance_n_minus_1 = int(self.data['n-1']['balances'][denom])
                balance_n = int(self.data['n']['balances'][denom])
                if balance_n != balance_n_minus_1:
                    logging.error(f"Balance for denom {denom} is incorrect. Expected {balance_n_minus_1}, got {balance_n}.")
                    self.data['checks'][denom] = {
                        'status': 'FAIL',
                        'expected_balance': balance_n_minus_1,
                        'actual_balance': balance_n
                    }
                else:
                    logging.info(f"Balance for denom {denom} is correct.")
                    self.data['checks'][denom] = {
                        'status': 'PASS',
                        'expected_balance': balance_n_minus_1,
                        'actual_balance': balance_n
                    }

    def check(self):
        """
        Check each of the fields and verify that the new balances are correct.
        """
        self.check_balances()

        # print(json.dumps(self.data['checks'], indent=4))

    def save(self):
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
    parser.add_argument('--output', type=str, default='rewards-check',
                        help='Output file name prefix (default: rewards-check-<height>.json)')
    
    args = parser.parse_args()
    
    rc = RewardsCheck(urlAPI=args.api, urlRPC=args.rpc, binary=args.binary, height=args.height, ics_removal_upgrade=args.ics_removal_upgrade, output_prefix=args.output)
    rc.collect_inputs()
    rc.check()
    rc.save()
