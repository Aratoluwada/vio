from fastapi.testclient import TestClient

from vio_backend.main import app


def test_liveness_is_available_without_database():
    with TestClient(app) as client:
        response = client.get("/health/live")
    assert response.status_code == 200
    assert response.json() == {"status": "alive"}


def test_readiness_fails_closed_without_database_configuration():
    with TestClient(app) as client:
        response = client.get("/health/ready")
    assert response.status_code == 503
    assert response.json()["detail"] == "Database is not configured"
