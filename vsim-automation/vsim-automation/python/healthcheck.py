#!/usr/bin/env python3
"""healthcheck.py - HTTP health probe with retries and logging (stdlib only).

Exit codes: 0 = healthy, 1 = unhealthy after all retries, 2 = bad arguments.
Example:  python3 healthcheck.py --url http://localhost:8080 --retries 5
"""
import argparse
import logging
import sys
import time
import urllib.error
import urllib.request


def check(url: str, timeout: float) -> bool:
    """Return True if the URL answers with an HTTP 2xx status."""
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            logging.info("GET %s -> HTTP %s", url, resp.status)
            return 200 <= resp.status < 300
    except urllib.error.HTTPError as exc:
        logging.warning("HTTP error from %s: %s", url, exc.code)
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        logging.warning("Connection problem for %s: %s", url, exc)
    return False


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--url", required=True)
    p.add_argument("--retries", type=int, default=5)
    p.add_argument("--delay", type=float, default=3.0, help="seconds between tries")
    p.add_argument("--timeout", type=float, default=5.0)
    p.add_argument("--log-file", default=None)
    args = p.parse_args()
    if args.retries < 1:
        p.error("--retries must be >= 1")

    handlers = [logging.StreamHandler()]
    if args.log_file:
        handlers.append(logging.FileHandler(args.log_file))
    logging.basicConfig(level=logging.INFO, handlers=handlers,
                        format="%(asctime)s [%(levelname)s] [healthcheck.py] %(message)s")

    for attempt in range(1, args.retries + 1):
        if check(args.url, args.timeout):
            logging.info("Service healthy (attempt %d/%d)", attempt, args.retries)
            return 0
        if attempt < args.retries:
            time.sleep(args.delay)
    logging.error("Service unhealthy after %d attempts", args.retries)
    return 1


if __name__ == "__main__":
    sys.exit(main())
