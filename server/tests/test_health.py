from conftest import PASS


def test_health_open(client):
    r = client.get("/api/health")
    assert r.status_code == 200
    assert r.json() == {"ok": True}


def test_health_reports_passcode(client):
    assert client.get("/api/health", headers=PASS).json() == {"ok": True, "passcode_ok": True}
    assert client.get("/api/health", headers={"Authorization": "Bearer nope"}).json() == {"ok": True, "passcode_ok": False}
