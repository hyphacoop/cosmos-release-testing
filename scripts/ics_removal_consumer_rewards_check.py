"""
Consumer Rewards Check
1. Verify that the balances from the consumer rewards pool are transferred to the community pool
2. Verify that the total supply for each of the tokens in the consumer rewards pool remains unchanged
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


def api_get_total_supply(urlAPI: str, height: int = 0):
    """
    Returns the total supply for a specific denom.
    Endpoint: GET /cosmos/bank/v1beta1/supply/by_denom?denom={denom}
    Response: {'amount': {'denom': str, 'amount': str}}
    Note: this endpoint returns a single coin, so no pagination is needed.
    """
    endpoint = f"{urlAPI}/cosmos/bank/v1beta1/supply"
    if height:
        response = requests.get(
            endpoint, headers={"x-cosmos-block-height": f"{height}"}
        ).json()
    else:
        response = requests.get(endpoint).json()
    if "supply" in response:
        return response["supply"]
    return []


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


def api_get_balances(urlAPI: str, address: str, height: int = 0):
    endpoint = f"{urlAPI}/cosmos/bank/v1beta1/balances/{address}"
    if height:
        response = requests.get(
            endpoint, headers={"x-cosmos-block-height": f"{height}"}
        ).json()
    else:
        response = requests.get(endpoint).json()
    if 'code' in response and response['code'] != 0:
        logging.error(f"Error fetching balances for address {address}: {response['message']}")
        return
    return response['balances']

def api_get_community_pool(urlAPI: str, height: int = 0):
    endpoint = f"{urlAPI}/cosmos/distribution/v1beta1/community_pool"
    if height:
        response = requests.get(
            endpoint, headers={"x-cosmos-block-height": f"{height}"}
        ).json()
    else:
        response = requests.get(endpoint).json()
    if 'code' in response and response['code'] != 0:
        logging.error(f"Error fetching community pool: {response['message']}")
        return
    return response['pool']


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
            'consumer_rewards_pool': {},
            'community_pool': {}
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


    def get_consumer_rewards_balances(self):
        pool = api_get_balances(self.urlAPI, self.CONSUMER_REWARDS_POOL_ADDRESS, height=self.height)
        denoms = set()
        print(f'Consumer rewards pool balances at height {self.height}:{pool}')
        for coin in pool:
            denoms.add(coin['denom'])
            self.data['consumer_rewards_pool'][coin['denom']] = coin['amount']
        self.data['consumer_rewards_denoms'] = list(denoms)

    def get_community_pool_balances(self):
        pool = api_get_community_pool(self.urlAPI, height=self.height)
        for coin in pool:
            self.data['community_pool'][coin['denom']] = coin['amount']

    def get_supplies(self):
        for coin in api_get_total_supply(self.urlAPI, height=self.height):
            denom = coin['denom']
            amount = coin['amount']
            self.data['balances'][denom] = amount

    def collect(self):
        # 0. Get block height if not provided
        if self.height == 0:
            self.height = rpc_get_current_height(self.urlRPC)
            self.data['height'] = self.height   
        
        self.get_consumer_rewards_balances()
        self.get_community_pool_balances()
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

        rewards_info_n_minus_2 = RewardsInfo(urlAPI=self.urlAPI, urlRPC=self.urlRPC, binary=self.binary, height=self.height-2)
        rewards_info_n_minus_1 = RewardsInfo(urlAPI=self.urlAPI, urlRPC=self.urlRPC, binary=self.binary, height=self.height-1)
        rewards_info_n = RewardsInfo(urlAPI=self.urlAPI, urlRPC=self.urlRPC, binary=self.binary, height=self.height)
        rewards_info_n_plus_1 = RewardsInfo(urlAPI=self.urlAPI, urlRPC=self.urlRPC, binary=self.binary, height=self.height+1)

        
        rewards_info_n_minus_2.collect()
        rewards_info_n_minus_1.collect()
        rewards_info_n.collect()
        rewards_info_n_plus_1.collect()
        self.data['n-2'] = rewards_info_n_minus_2.data
        self.data['n-1'] = rewards_info_n_minus_1.data
        self.data['n'] = rewards_info_n.data
        self.data['n+1'] = rewards_info_n_plus_1.data

        print(f'Rewards data: {json.dumps(self.data, indent=4)}')
        

    def check_community_pool_transfer(self):
        """
        Check that the balances for the consumer rewards denoms are correct based on the rewards distribution and the supplies.
        """
        if self.ics_disable_upgrade:
            # For each denom in the consumer rewards pool:
            # 1. The balance in the community pool should increase by that amount
            # 2. The balance in the consumer rewards pool should decrease by that amount
            for denom, amount in self.data['n-1']['consumer_rewards_pool'].items():
                print(f'Checking denom {denom} with amount {amount} in consumer rewards pool at height n-1.')
                amount_n = int(self.data['n']['consumer_rewards_pool'].get(denom, 0))
                amount_n_minus_1 = int(amount)
                transferred_amount = amount_n_minus_1 - amount_n
                print(f'Transferred amount for denom {denom}: {transferred_amount}')
                if denom not in self.data['n']['community_pool']:
                    community_pool_amount_n = 0
                else:
                    cp_amount_n = self.data['n']['community_pool'].get(denom, 0)
                    print(f'amount_n: {cp_amount_n}')
                    community_pool_amount_n = int(float(cp_amount_n))

                if denom not in self.data['n-1']['community_pool']:
                    community_pool_amount_n_minus_1 = 0
                else:
                    cp_n_minus_1 = self.data['n-1']['community_pool'].get(denom, 0)
                    print(f'amount_n_minus_1: {cp_n_minus_1}')
                    community_pool_amount_n_minus_1 = int(float(cp_n_minus_1))
                community_pool_increase = community_pool_amount_n - community_pool_amount_n_minus_1
                check_passed = transferred_amount == community_pool_increase
                self.data['checks'][f'community_pool_transfer_{denom}'] = {
                    'transferred_amount': transferred_amount,
                    'community_pool_increase': community_pool_increase,
                    'check_passed': check_passed
                }

    def check_supply_unchanged(self):
        # For each denom in the consumer rewards pool, check that the total supply remains unchanged
        for denom in self.data['n-1']['consumer_rewards_denoms']:
            supply_n = int(self.data['n']['balances'].get(denom, 0))
            supply_n_minus_1 = int(self.data['n-1']['balances'].get(denom, 0))
            supply_change = supply_n - supply_n_minus_1
            check_passed = supply_change == 0
            self.data['checks'][f'supply_unchanged_{denom}'] = {
                'supply_n': supply_n,
                'supply_n_minus_1': supply_n_minus_1,
                'supply_change': supply_change,
                'check_passed': check_passed
            }

    def check(self):
        """
        Check each of the fields and verify that the new balances are correct.
        """
        logging.info(f"Checking rewards distribution changes at heights n-1 ({self.height-1}) and n ({self.height}).")

        if self.ics_disable_upgrade:
            self.check_community_pool_transfer()
        self.check_supply_unchanged()

        print(json.dumps(self.data['checks'], indent=4))

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
    parser.add_argument('--output', type=str, default='rewards-check',
                        help='Output file name prefix (default: rewards-check-<height>.json)')
    
    args = parser.parse_args()
    
    rc = RewardsCheck(urlAPI=args.api, urlRPC=args.rpc, binary=args.binary, height=args.height, ics_removal_upgrade=args.ics_removal_upgrade, output_prefix=args.output)
    rc.collect_inputs()
    rc.check()
    rc.save()
