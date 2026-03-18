"""
IBC Channels Check
1. Verify that the IBC channels with port id "provider" have been closed after the ICS removal upgrade.
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


def api_get_ibc_channels(urlAPI: str, height: int = 0):
    endpoint = f"{urlAPI}/ibc/core/channel/v1/channels?pagination.limit=1000"
    headers = {"x-cosmos-block-height": f"{height}"} if height else {}
    response = requests.get(endpoint, headers=headers).json()
    if "channels" not in response:
        return []
    channels = response["channels"]
    next_key = response["pagination"]["next_key"]
    while next_key:
        response = requests.get(
            f"{urlAPI}/ibc/core/channel/v1/channels?pagination.limit=1000&pagination.key="
            f"{urllib.parse.quote(next_key)}",
            headers=headers,
        ).json()
        channels.extend(response["channels"])
        next_key = response["pagination"]["next_key"]
    return channels



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



class ChannelsCheck():
    def __init__(self,
                urlAPI: str='http://localhost:25001',
                urlRPC: str='http://localhost:27001',
                binary: str='gaiad',
                height: int=0,
                ics_removal_upgrade: bool=False,
                output_prefix: str='channels-check'):
        
        self.urlAPI = urlAPI
        self.urlRPC = urlRPC
        self.binary = binary
        self.height = height
        self.output_prefix = output_prefix
        self.data = {'checks': {}}
        self.ics_disable_upgrade = ics_removal_upgrade


    def check(self):
        """
        Check each of the fields and verify that the new balances are correct.
        """
        logging.info(f"Checking status of provider port channels at height {self.height}.")
        channels = api_get_ibc_channels(self.urlAPI, height=self.height)
        provider_port_channels = [channel for channel in channels if channel['port_id'] == 'provider']

        print(f'Found {len(provider_port_channels)} channels with provider port: {provider_port_channels}')

        if not self.ics_disable_upgrade:
             logging.info("Upgrade is not the ICS removal upgrade, skipping provider port channels check.")
             return

        if len(provider_port_channels) == 0:
            self.data['checks']['provider_port_channels'] = 'PASS'
        else:
            self.data['checks']['provider_port_channels'] = 'FAIL'
            self.data['checks']['provider_port_channels_details'] = f'Expected 0 channels with provider port, found {len(provider_port_channels)}: {provider_port_channels}'

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
    parser.add_argument('--output', type=str, default='channels-check',
                        help='Output file name prefix (default: channels-check-<height>.json)')
    
    args = parser.parse_args()
    
    rc = ChannelsCheck(urlAPI=args.api, urlRPC=args.rpc, binary=args.binary, height=args.height, ics_removal_upgrade=args.ics_removal_upgrade, output_prefix=args.output)
    rc.collect_inputs()
    rc.check()
    rc.save()
