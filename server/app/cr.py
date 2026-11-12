"""tools/cr_from_inspection.py used as a module (docs/06-backend.md, Build pipeline)."""
import sys

from . import config

sys.path.insert(0, str(config.TOOLS_DIR))
from cr_from_inspection import CAT, PAINT_SHOWN, SPIN_SLOTS, build_cr, renamed, vin_ok  # noqa: E402,F401
