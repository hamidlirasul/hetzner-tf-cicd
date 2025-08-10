from flask import Flask
app = Flask(__name__)

@app.get("/")
def hello():
    return "Hello from MPay demo on Hetzner via Terraform + GitHub Actions!\n"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)

