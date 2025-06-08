import os
from pymongo import MongoClient
from dotenv import load_dotenv
import certifi

def export_unused_activation_codes(output_filename="unused_activation_codes.txt"):
    """Connects to MongoDB, retrieves unused activation codes, and writes them to a file."""
    load_dotenv()

    mongo_uri = os.getenv("MONGO_URI")
    if not mongo_uri:
        print("Error: MONGO_URI not found in .env file.")
        return

    try:
        client = MongoClient(mongo_uri, tlsCAFile=certifi.where())
        db = client['voicememos_db'] 
        activation_codes_collection = db["activation_codes"]

        print(f"Connected to MongoDB. Database: {db.name}, Collection: {activation_codes_collection.name}")

        # Find codes where 'used' is False
        unused_codes_cursor = activation_codes_collection.find({"used": False})
        
        codes_to_write = []
        for doc in unused_codes_cursor:
            if 'code' in doc:
                codes_to_write.append(doc['code'])
        
        if not codes_to_write:
            print("No unused activation codes found.")
            return

        # Get the absolute path for the output file in the same directory as the script
        script_dir = os.path.dirname(os.path.abspath(__file__))
        output_filepath = os.path.join(script_dir, output_filename)

        with open(output_filepath, 'w') as f:
            for code in codes_to_write:
                f.write(code + '\n')
        
        print(f"Successfully wrote {len(codes_to_write)} unused activation codes to {output_filepath}")

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        if 'client' in locals() and client:
            client.close()
            print("MongoDB connection closed.")

if __name__ == "__main__":
    print("Attempting to export unused activation codes...")
    export_unused_activation_codes()
