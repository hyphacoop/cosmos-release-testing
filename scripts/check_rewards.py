import argparse
import json

parser = argparse.ArgumentParser()
parser.add_argument('denoms', metavar='d', type=str, nargs=2)
parser.add_argument('--equal', action='store_true')

args = parser.parse_args()


print(args.denoms)
print(args.equal)