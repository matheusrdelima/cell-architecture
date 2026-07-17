import os
import time
from flask import Flask, jsonify
import psycopg2

app = Flask(__name__)

CELL_ID = os.environ.get("CELL_ID", "unknown")
DB_HOST = os.environ.get("DB_HOST", "cell-db")
DB_NAME = os.environ.get("DB_NAME", "cellsdb")
DB_USER = os.environ.get("DB_USER", "celluser")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "cellpass")


def get_conn():
    return psycopg2.connect(
        host=DB_HOST, dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD
    )


def init_db():
    for attempt in range(30):
        try:
            conn = get_conn()
            cur = conn.cursor()
            cur.execute(
                "CREATE TABLE IF NOT EXISTS visits "
                "(id SERIAL PRIMARY KEY, ts TIMESTAMP DEFAULT now())"
            )
            conn.commit()
            cur.close()
            conn.close()
            print("DB pronta.")
            return
        except Exception as e:
            print(f"Aguardando banco de dados... tentativa {attempt+1}: {e}")
            time.sleep(2)
    raise RuntimeError("Não foi possível conectar ao banco de dados")


@app.route("/")
def index():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("INSERT INTO visits DEFAULT VALUES")
    conn.commit()
    cur.execute("SELECT count(*) FROM visits")
    count = cur.fetchone()[0]
    cur.close()
    conn.close()
    return jsonify(
        {
            "cell": CELL_ID,
            "message": f"Hello from cell {CELL_ID}",
            "visits_registradas_no_banco_desta_celula": count,
            "pod": os.environ.get("HOSTNAME"),
        }
    )


@app.route("/health")
def health():
    return jsonify({"status": "ok", "cell": CELL_ID})


if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=8080)
