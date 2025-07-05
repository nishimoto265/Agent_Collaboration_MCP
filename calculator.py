#!/usr/bin/env python3
"""Simple calculator program with addition and subtraction."""


def add(a, b):
    """Add two numbers."""
    return a + b


def subtract(a, b):
    """Subtract b from a."""
    return a - b


def main():
    print("Simple Calculator")
    print("================")
    print("Operations:")
    print("1. Addition (a + b)")
    print("2. Subtraction (a - b)")
    print("3. Exit")
    
    while True:
        try:
            choice = input("\nSelect operation (1-3): ")
            
            if choice == '3':
                print("Goodbye!")
                break
                
            if choice not in ['1', '2']:
                print("Invalid choice. Please select 1, 2, or 3.")
                continue
                
            num1 = float(input("Enter first number: "))
            num2 = float(input("Enter second number: "))
            
            if choice == '1':
                result = add(num1, num2)
                print(f"{num1} + {num2} = {result}")
            elif choice == '2':
                result = subtract(num1, num2)
                print(f"{num1} - {num2} = {result}")
                
        except ValueError:
            print("Invalid input. Please enter valid numbers.")
        except KeyboardInterrupt:
            print("\nExiting...")
            break
        except Exception as e:
            print(f"An error occurred: {e}")


if __name__ == "__main__":
    main()