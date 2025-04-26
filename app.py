from flask import Flask, request, jsonify
import psycopg2
import os

app = Flask(__name__)

# Database connection parameters from environment variables
DB_HOST = os.environ['DB_HOST']
DB_NAME = os.environ['DB_NAME']
DB_USER = os.environ['DB_USER']
DB_PASS = os.environ['DB_PASS']

def get_db_connection():
    return psycopg2.connect(
        host=DB_HOST,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASS
    )

@app.route('/')
def index():
    return "Welcome to the Flask ECS App!"

@app.route('/add', methods=['POST'])
def add_data():
    data = request.json
    name = data.get('name')
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("INSERT INTO users (name) VALUES (%s);", (name,))
    conn.commit()
    cur.close()
    conn.close()
    return jsonify({"message": f"{name} added!"})

@app.route('/users', methods=['GET'])
def get_users():
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("SELECT * FROM users;")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return jsonify(rows)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
