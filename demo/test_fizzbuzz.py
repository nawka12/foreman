import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fizzbuzz import fizzbuzz

assert fizzbuzz(3) == "Fizz"
assert fizzbuzz(5) == "Buzz"
assert fizzbuzz(15) == "FizzBuzz"
assert fizzbuzz(2) == "2"

print("OK")
