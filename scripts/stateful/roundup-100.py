#!/usr/bin/env python
import sys
import math

def roundup(x):
    result = int(math.ceil(x / 100.0)) * 100
    print(result)
    return
input = int(sys.argv[1]) + 1

roundup(input)
