"""Incident Tracker: a small three-tier sample app (nginx -> gunicorn/Flask -> Postgres)."""
import os
from datetime import datetime, timezone

from flask import Flask, jsonify, request, send_from_directory
from flask_sqlalchemy import SQLAlchemy
from prometheus_client import CONTENT_TYPE_LATEST, Counter, generate_latest
from sqlalchemy import text

db = SQLAlchemy()

REQUESTS = Counter(
    "incident_api_requests_total",
    "HTTP requests handled by the API",
    ["method", "endpoint", "status"],
)

SEVERITIES = {"SEV1", "SEV2", "SEV3", "SEV4"}
STATUSES = {"open", "investigating", "resolved"}


class Incident(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    severity = db.Column(db.String(10), nullable=False, default="SEV3")
    status = db.Column(db.String(20), nullable=False, default="open")
    created_at = db.Column(
        db.DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )

    def to_dict(self):
        return {
            "id": self.id,
            "title": self.title,
            "severity": self.severity,
            "status": self.status,
            "created_at": self.created_at.isoformat(),
        }


def create_app(config=None):
    app = Flask(__name__, static_folder="static", static_url_path="/static")
    app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get(
        "DATABASE_URL", "sqlite:///incidents.db"
    )
    app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
    if config:
        app.config.update(config)

    db.init_app(app)
    with app.app_context():
        db.create_all()

    @app.after_request
    def count_request(response):
        endpoint = request.url_rule.rule if request.url_rule else "unmatched"
        if endpoint != "/metrics":
            REQUESTS.labels(request.method, endpoint, response.status_code).inc()
        return response

    @app.get("/")
    def index():
        return send_from_directory(app.static_folder, "index.html")

    @app.get("/healthz")
    def healthz():
        """Liveness plus a database round-trip, for load balancer probes."""
        try:
            db.session.execute(text("SELECT 1"))
        except Exception:  # noqa: BLE001 - any DB failure means unhealthy
            return jsonify(status="unhealthy", database="down"), 503
        return jsonify(status="ok", database="up")

    @app.get("/metrics")
    def metrics():
        return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}

    @app.get("/api/incidents")
    def list_incidents():
        rows = Incident.query.order_by(Incident.created_at.desc()).all()
        return jsonify([r.to_dict() for r in rows])

    @app.post("/api/incidents")
    def create_incident():
        data = request.get_json(silent=True) or {}
        title = (data.get("title") or "").strip()
        severity = data.get("severity", "SEV3")
        if not title or len(title) > 200:
            return jsonify(error="title is required (max 200 chars)"), 400
        if severity not in SEVERITIES:
            return jsonify(error=f"severity must be one of {sorted(SEVERITIES)}"), 400
        incident = Incident(title=title, severity=severity)
        db.session.add(incident)
        db.session.commit()
        return jsonify(incident.to_dict()), 201

    @app.patch("/api/incidents/<int:incident_id>")
    def update_incident(incident_id):
        incident = db.session.get(Incident, incident_id)
        if incident is None:
            return jsonify(error="not found"), 404
        data = request.get_json(silent=True) or {}
        status = data.get("status")
        if status not in STATUSES:
            return jsonify(error=f"status must be one of {sorted(STATUSES)}"), 400
        incident.status = status
        db.session.commit()
        return jsonify(incident.to_dict())

    return app


app = create_app() if os.environ.get("CREATE_APP_ON_IMPORT", "1") == "1" else None

if __name__ == "__main__":
    create_app().run(host="127.0.0.1", port=8000)
