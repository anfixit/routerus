import requests
import sys

try:
    response = requests.get('http://localhost:8000/docs')
    print(f"API Status Code: {response.status_code}")
    print("API is accessible!")
    sys.exit(0)
except Exception as e:
    print(f"Error accessing API: {str(e)}")
    sys.exit(1)
