"""Render T3 connection details with the sandbox's published address."""

import re
import sys
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit


QR_CHARACTERS = frozenset(" \t\r\n█▀▄")


def pairing_url(public_url, original):
    source = urlsplit(original)
    target = urlsplit(public_url)
    if source.scheme != "http" or source.port != target.port:
        return original
    return urlunsplit((target.scheme, target.netloc, "/pair", source.query, source.fragment))


def render_qr(value):
    import qrcode

    qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, border=2)
    qr.add_data(value, optimize=0)
    qr.make(fit=True)
    matrix = qr.get_matrix()
    rows = []
    for y in range(0, len(matrix), 2):
        row = []
        for x, top_dark in enumerate(matrix[y]):
            bottom_dark = y + 1 < len(matrix) and matrix[y + 1][x]
            row.append(("█" if bottom_dark else "▀") if top_dark else ("▄" if bottom_dark else " "))
        rows.append("".join(row))
    return "\n".join(rows) + "\n"


def rewrite(lines, public_url, output):
    current_pairing_url = None
    pending_qr = []
    in_qr = False
    for line in lines:
        if line.strip() and set(line) <= QR_CHARACTERS:
            if not in_qr and current_pairing_url:
                output.write(render_qr(current_pairing_url))
                output.flush()
            in_qr = True
            if current_pairing_url is None:
                pending_qr.append(line)
            continue
        if in_qr and not line.strip():
            continue
        in_qr = False

        if line.startswith("Pairing URL: "):
            current_pairing_url = pairing_url(public_url, line[len("Pairing URL: "):].strip())
            if pending_qr:
                output.write(render_qr(current_pairing_url) + "\n")
                pending_qr.clear()
            line = f"Pairing URL: {current_pairing_url}\n"
        elif pending_qr:
            output.writelines(pending_qr)
            pending_qr.clear()

        if line.startswith("Connection string: "):
            original = urlsplit(line[len("Connection string: "):].strip())
            if original.scheme == "http" and original.port == urlsplit(public_url).port:
                line = f"Connection string: {public_url}\n"
        elif line.startswith("App link: "):
            link = urlsplit(line[len("App link: "):].strip())
            query = [(key, pairing_url(public_url, value) if urlsplit(value).path == "/pair" else value)
                     for key, value in parse_qsl(link.query, keep_blank_values=True)]
            line = "App link: " + urlunsplit(link._replace(query=urlencode(query))) + "\n"
        elif "pairingUrl: " in line:
            line = re.sub(r"(?<=pairingUrl: )https?://[^\s]+", lambda match: pairing_url(public_url, match[0]), line)
        output.write(line)
        output.flush()
    output.writelines(pending_qr)


if __name__ == "__main__":
    try:
        rewrite(sys.stdin, sys.argv[1].rstrip("/"), sys.stdout)
    except BrokenPipeError:
        sys.exit(1)
