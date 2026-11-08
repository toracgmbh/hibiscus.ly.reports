#!/usr/bin/env python3
"""Setzt Version und <url> in einer plugin.xml, ohne den Rest der Datei anzufassen.

Aufruf:  python3 -I torac/patch-plugin-xml.py <plugin.xml> <ausgabe> <plugin-name> <version> <url>

Die Datei wird zuerst als XML gelesen und geprüft: Wurzelelement <plugin> mit dem
erwarteten Namen und einem version-Attribut, genau ein <url>-Element (direkt unter
der Wurzel). Danach werden nur das version-Attribut des Wurzelelements und der Text
dieses <url>-Elements im Quelltext ersetzt (Kommentare und Formatierung bleiben
erhalten, die Werte werden XML-escaped). Das Ergebnis wird erneut gelesen und
geprüft. Jede Abweichung beendet das Skript mit einer Meldung und Exit-Code 1.
"""
import re
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape, quoteattr


def fail(message):
    print("plugin.xml: " + message, file=sys.stderr)
    sys.exit(1)


def local(tag):
    return tag.rsplit("}", 1)[-1]


def check(path, name, version=None, url=None):
    """Prüft die Struktur; mit version/url zusätzlich die erwarteten Werte."""
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, OSError) as e:
        fail("%s ist kein wohlgeformtes XML: %s" % (path, e))
    if local(root.tag) != "plugin":
        fail("Wurzelelement ist <%s>, erwartet <plugin>" % local(root.tag))
    if root.get("name") != name:
        fail("Plugin-Name ist %r, erwartet %r" % (root.get("name"), name))
    if root.get("version") is None:
        fail("Wurzelelement hat kein version-Attribut")
    all_urls = [e for e in root.iter() if local(e.tag) == "url"]
    direct_urls = [e for e in root if local(e.tag) == "url"]
    if len(all_urls) != 1 or len(direct_urls) != 1:
        fail("erwartet genau ein <url>-Element unter <plugin>, gefunden: %d" % len(all_urls))
    if version is not None and root.get("version") != version:
        fail("version ist %r, erwartet %r" % (root.get("version"), version))
    if url is not None and (direct_urls[0].text or "") != url:
        fail("<url> ist %r, erwartet %r" % (direct_urls[0].text, url))


def main():
    if len(sys.argv) != 6:
        fail("Aufruf: patch-plugin-xml.py <plugin.xml> <ausgabe> <plugin-name> <version> <url>")
    src, dst, name, version, url = sys.argv[1:]
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        fail("Version %r ist nicht von der Form X.Y.Z" % version)
    if not re.fullmatch(r"https://[A-Za-z0-9._~/-]+", url):
        fail("URL %r enthält unerwartete Zeichen" % url)

    check(src, name)
    with open(src, encoding="utf-8") as f:
        text = f.read()

    # Start-Tag des Wurzelelements: das erste Element nach Prolog und Kommentaren.
    prolog = re.compile(r"\A(?:\s|<\?.*?\?>|<!--.*?-->)*", re.S)
    start = prolog.match(text).end()
    tag = re.compile(r"<plugin(?=[\s>/])[^>]*>").match(text, start)
    if not tag:
        fail("Start-Tag des Wurzelelements nicht gefunden")
    new_tag, n = re.subn(r'(\sversion=)("[^"]*"|\'[^\']*\')',
                         lambda m: m.group(1) + quoteattr(version), tag.group(0))
    if n != 1:
        fail("erwartet genau ein version-Attribut im Wurzelelement, gefunden: %d" % n)
    text = text[:tag.start()] + new_tag + text[tag.end():]

    text, n = re.subn(r"<url>[^<]*</url>", lambda m: "<url>" + escape(url) + "</url>", text)
    if n != 1:
        fail("erwartet genau ein <url>-Element im Quelltext, ersetzt: %d" % n)

    with open(dst, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    check(dst, name, version, url)


main()
