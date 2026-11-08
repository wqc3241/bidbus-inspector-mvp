"""NHTSA vPIC VIN decode, reduced to the New inspection fields."""
import httpx

URL = "https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues/{}?format=json"


def fuel(r: dict) -> str:
    el, ft = (r.get("ElectrificationLevel") or "").upper(), (r.get("FuelTypePrimary") or "").lower()
    if el.startswith("BEV") or ft == "electric":
        return "Electric (EV)"
    if el.startswith("PHEV"):
        return "Plug-in hybrid"
    if "HEV" in el:  # HEV, Strong HEV, Mild HEV
        return "Hybrid"
    return "Gas or diesel"


def decode(vin: str) -> dict:
    """raises httpx.HTTPError (or ValueError, KeyError) when vPIC fails"""
    resp = httpx.get(URL.format(vin), timeout=10)
    resp.raise_for_status()
    r = resp.json()["Results"][0]
    year = (r.get("ModelYear") or "").strip()
    return {"year": int(year) if year.isdigit() else None, "make": r.get("Make") or None, "model": r.get("Model") or None,
            "trim": r.get("Trim") or None, "fuel": fuel(r)}
