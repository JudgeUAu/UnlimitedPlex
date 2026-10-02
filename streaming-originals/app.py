import threading

import requests
from flask import Flask, jsonify, render_template, request

import engine

app = Flask(__name__)
runner = engine.Runner()
threading.Thread(target=engine.scheduler_loop, args=(runner,), daemon=True).start()


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/config", methods=["GET"])
def get_config():
    return jsonify(engine.masked(engine.load_config()))


@app.route("/api/config", methods=["POST"])
def set_config():
    new = request.get_json(force=True)
    engine.save_config(new)
    return jsonify({"saved": True})


@app.route("/api/state")
def state():
    return jsonify(runner.state)


@app.route("/api/run", methods=["POST"])
def run():
    dry = bool((request.get_json(silent=True) or {}).get("dry", True))
    if not runner.start(dry):
        return jsonify({"error": "A run is already in progress"}), 409
    return jsonify({"started": True, "dry": dry})


@app.route("/api/history")
def history():
    return jsonify(engine._read_json(engine.HIST_PATH, [])[:200])


@app.route("/api/test-target", methods=["POST"])
def test_target():
    """Test a target (as currently edited in the UI) and return its folders/profiles."""
    t = request.get_json(force=True)
    if t.get("api_key") == engine.MASK:
        for old in engine.load_config()["targets"]:
            if old["name"] == t.get("name"):
                t["api_key"] = old["api_key"]
    try:
        return jsonify({"ok": True, **engine.Arr(dict(engine.DEFAULT_TARGET, **t)).info()})
    except requests.RequestException as e:
        return jsonify({"ok": False, "error": str(e)}), 200
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=7501, debug=False)
