import os
import json
import base64
import boto3
import mysql.connector


SECRET_NAME = os.getenv("SECRET_NAME", "invitime-dev-db-credentials")  # 환경에 맞게 변경
AWS_REGION  = os.getenv("AWS_REGION", "ap-northeast-2")

def get_secret_dict(secret_name: str, region_name: str) -> dict:
    sm = boto3.client("secretsmanager", region_name=region_name, aws_access_key_id=AWS_ACCESS_KEY_ID, aws_secret_access_key=AWS_SECRET_ACCESS_KEY)
    resp = sm.get_secret_value(SecretId=secret_name)
    if "SecretString" in resp:
        return json.loads(resp["SecretString"])
    return json.loads(base64.b64decode(resp["SecretBinary"]))

def main():
    s = get_secret_dict(SECRET_NAME, AWS_REGION)
    # RDS 시크릿 키 구조: username, password, host, port, dbname
    cfg = {
        "host": s["host"],
        "port": int(s.get("port", 3306)),
        "user": s["username"],
        "password": s["password"],
        "database": s["dbname"],
    }
    print(cfg)
    conn = mysql.connector.connect(**cfg)
    try:
        cur = conn.cursor()
        cur.execute("SELECT VERSION(), CURRENT_USER(), DATABASE()")
        version, current_user, db = cur.fetchone()
        print(f"MySQL VERSION={version}, USER={current_user}, DB={db}")
        cur.execute("SHOW TABLES")
        print("Tables:", [r[0] for r in cur.fetchall()])
    finally:
        conn.close()

if __name__ == "__main__":
    main()