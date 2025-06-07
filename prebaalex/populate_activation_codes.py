import os
from pymongo import MongoClient, errors
from dotenv import load_dotenv

def populate_codes():
    """
    Connects to MongoDB and populates the activation_codes collection
    with a predefined list of codes.
    """
    load_dotenv()  # Load environment variables from .env file

    mongo_uri = os.getenv("MONGO_URI")
    if not mongo_uri:
        print("Error: MONGO_URI not found in .env file. Please ensure it is set.")
        return

    try:
        client = MongoClient(mongo_uri)
        # Verify connection
        client.admin.command('ping') 
    except errors.ConnectionFailure as e:
        print(f"MongoDB Connection Failed: {e}")
        return
    except Exception as e:
        print(f"An error occurred during MongoDB connection: {e}")
        return

    db = client.voicememos_db  # Your database name
    activation_codes_collection = db.activation_codes

    # List of activation codes to add
    # You can add a 'description' field for your own reference
    codes_to_add = [
        {"code": "WELCOME2025", "used": False, "description": "General welcome code for new users"},
        {"code": "TESTDRIVE001", "used": False, "description": "Code for initial testing"},
        {"code": "BETAUSERXYZ", "used": False, "description": "Code for beta program participants"},
        {"code": "ALEXSPECIAL", "used": False, "description": "A special code for Alex"}
    ]

    added_count = 0
    skipped_count = 0

    print(f"Attempting to add {len(codes_to_add)} codes to the '{activation_codes_collection.name}' collection in database '{db.name}'...")

    for code_doc in codes_to_add:
        try:
            # Check if a code with the same 'code' value already exists
            existing_code = activation_codes_collection.find_one({"code": code_doc["code"]})
            if existing_code:
                print(f"Code '{code_doc['code']}' already exists. Skipping.")
                skipped_count += 1
            else:
                activation_codes_collection.insert_one(code_doc)
                print(f"Successfully added code: {code_doc['code']}")
                added_count += 1
        except errors.PyMongoError as e:
            print(f"MongoDB error while processing code '{code_doc['code']}': {e}")
        except Exception as e:
            print(f"An unexpected error occurred while processing code '{code_doc['code']}': {e}")


    print(f"\nPopulation complete.")
    print(f"Successfully added {added_count} new activation codes.")
    if skipped_count > 0:
        print(f"Skipped {skipped_count} codes that already existed.")
    
    client.close()
    print("MongoDB connection closed.")

if __name__ == "__main__":
    populate_codes()
