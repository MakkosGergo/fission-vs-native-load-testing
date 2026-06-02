def main():
    def fibonacci(n):
        if n <= 1:
            return n
        else:
            return(fibonacci(n-1) + fibonacci(n-2))
    
    eredmeny = fibonacci(30)
    return f"A 30. Fibonacci szam: {eredmeny}\n"
