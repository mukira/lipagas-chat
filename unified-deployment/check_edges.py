import os
import json
import psycopg2

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://typebot:postgres_password@localhost:5432/typebot")

def main():
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()
    
    # Check edges in PublicTypebot
    cur.execute("SELECT edges FROM \"PublicTypebot\" WHERE \"typebotId\" = (SELECT id FROM \"Typebot\" WHERE name = 'Presidential Bot');")
    row = cur.fetchone()
    if row:
        edges = row[0]
        found = any(e['id'] == 'edg_793c059e35594f1eb348' for e in edges)
        print("Edge edg_793c059e35594f1eb348 in PublicTypebot?", found)
        if not found:
            # We need to copy edges from Typebot to PublicTypebot
            cur.execute("SELECT edges FROM \"Typebot\" WHERE name = 'Presidential Bot';")
            typebot_edges = cur.fetchone()[0]
            cur.execute("UPDATE \"PublicTypebot\" SET edges = %s WHERE \"typebotId\" = (SELECT id FROM \"Typebot\" WHERE name = 'Presidential Bot')", (json.dumps(typebot_edges),))
            conn.commit()
            print("Copied edges to PublicTypebot!")
    else:
        print("Bot not found in PublicTypebot")
        
if __name__ == "__main__":
    main()
