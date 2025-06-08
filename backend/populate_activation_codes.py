import os
import random
import string
from pymongo import MongoClient
from dotenv import load_dotenv
import certifi # Added certifi import

def generate_random_code(length=12):
    """Generates a random alphanumeric code."""
    characters = string.ascii_letters + string.digits
    return ''.join(random.choice(characters) for i in range(length))

def populate_activation_codes(num_codes_to_generate=100):
    """Connects to MongoDB and populates the activation_codes collection."""
    load_dotenv()

    mongo_uri = os.getenv("MONGO_URI")
    if not mongo_uri:
        print("Error: MONGO_URI not found in .env file.")
        return

    try:
        # Added tlsCAFile=certifi.where() to MongoClient connection
        client = MongoClient(mongo_uri, tlsCAFile=certifi.where())
        db = client['voicememos_db'] # Explicitly set database name

        activation_codes_collection = db["activation_codes"]

        print(f"Connected to MongoDB. Database: {db.name}, Collection: {activation_codes_collection.name}")

        codes_to_insert = []
        for _ in range(num_codes_to_generate):
            code = generate_random_code()
            # MongoDB will automatically generate an _id if it's not provided
            code_document = {
                "code": code,
                "used": False
            }
            codes_to_insert.append(code_document)
        
        if codes_to_insert:
            result = activation_codes_collection.insert_many(codes_to_insert)
            print(f"Successfully inserted {len(result.inserted_ids)} new activation codes.")
        else:
            print("No codes were generated to insert.")

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        if 'client' in locals() and client:
            client.close()
            print("MongoDB connection closed.")

if __name__ == "__main__":
    # You can change the number of codes to generate here
    # For example, to generate 50 codes:
    number_of_codes = 50 
    print(f"Attempting to generate and insert {number_of_codes} activation codes...")
    populate_activation_codes(num_codes_to_generate=number_of_codes)
