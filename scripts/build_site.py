"""Build the planner page: site/template.html + site/app.js + data/items.js + build/gear.json -> build/index.html.

The workflow encrypts build/index.html with the page password afterwards (StatiCrypt).

Usage: python scripts/build_site.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main():
    template = (ROOT / "site" / "template.html").read_text(encoding="utf-8")
    app_js = (ROOT / "site" / "app.js").read_text(encoding="utf-8")
    items_js = (ROOT / "data" / "items.js").read_text(encoding="utf-8")
    gear_path = ROOT / "build" / "gear.json"
    gear = json.loads(gear_path.read_text(encoding="utf-8")) if gear_path.exists() else None

    mech_path = ROOT / "data" / "mechanics.json"
    mech = json.loads(mech_path.read_text(encoding="utf-8")) if mech_path.exists() else None
    data_js = (items_js + "\nwindow.GEAR_STATE = " + json.dumps(gear, separators=(",", ":")) + ";\n"
               + "window.MECH = " + json.dumps(mech, separators=(",", ":")) + ";\n")
    safe = lambda s: s.replace("</script", "<\\/script")  # noqa: E731
    for marker in ("/*__GEAR_DATA__*/", "/*__APP_JS__*/", "<!--BODY-->", "<!--LOCAL_ONLY-->"):
        assert marker in template, f"template is missing {marker}"
    page = template.replace("/*__GEAR_DATA__*/", safe(data_js)).replace("/*__APP_JS__*/", safe(app_js))
    head, body = page.split("<!--BODY-->")
    body = body.replace("<!--LOCAL_ONLY-->", "")  # item tooltips are the page's own (no Wowhead script)
    html = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
            '<meta name="robots" content="noindex, nofollow">\n'
            + head + '</head>\n<body>\n' + body + '</body>\n</html>\n')
    out = ROOT / "build" / "index.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html, encoding="utf-8")
    print(f"written {out} ({out.stat().st_size / 1024:.0f} KB), gear: {'yes' if gear else 'no'}")


if __name__ == "__main__":
    main()
