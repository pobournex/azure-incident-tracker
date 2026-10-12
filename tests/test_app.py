import os
import sys

import pytest

os.environ["CREATE_APP_ON_IMPORT"] = "0"
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))

from app import create_app, db  # noqa: E402


@pytest.fixture()
def client():
    app = create_app({"TESTING": True, "SQLALCHEMY_DATABASE_URI": "sqlite:///:memory:"})
    with app.app_context():
        db.create_all()
        yield app.test_client()
        db.session.remove()
        db.drop_all()


def test_healthz_reports_database_up(client):
    res = client.get("/healthz")
    assert res.status_code == 200
    assert res.get_json() == {"status": "ok", "database": "up"}


def test_create_and_list_incident(client):
    res = client.post("/api/incidents", json={"title": "API latency spike", "severity": "SEV2"})
    assert res.status_code == 201
    created = res.get_json()
    assert created["status"] == "open"

    listing = client.get("/api/incidents").get_json()
    assert [i["title"] for i in listing] == ["API latency spike"]


def test_create_rejects_missing_title(client):
    res = client.post("/api/incidents", json={"severity": "SEV1"})
    assert res.status_code == 400


def test_create_rejects_bad_severity(client):
    res = client.post("/api/incidents", json={"title": "x", "severity": "SEV9"})
    assert res.status_code == 400


def test_update_status(client):
    incident = client.post("/api/incidents", json={"title": "Disk full"}).get_json()
    res = client.patch(f"/api/incidents/{incident['id']}", json={"status": "resolved"})
    assert res.status_code == 200
    assert res.get_json()["status"] == "resolved"


def test_update_unknown_incident_returns_404(client):
    res = client.patch("/api/incidents/999", json={"status": "resolved"})
    assert res.status_code == 404


def test_update_rejects_bad_status(client):
    incident = client.post("/api/incidents", json={"title": "Disk full"}).get_json()
    res = client.patch(f"/api/incidents/{incident['id']}", json={"status": "banana"})
    assert res.status_code == 400


def test_metrics_exposes_request_counter(client):
    client.get("/api/incidents")
    body = client.get("/metrics").get_data(as_text=True)
    assert "incident_api_requests_total" in body
