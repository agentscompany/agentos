#!/usr/bin/env python3
"""pc ui | press N | set N "texto" — a página do Chromium do bot em texto, e ações pelo número do elemento.

Fala com o Chromium do perfil do bot pelo protocolo de depuração (CDP), na porta que ele anota em
<perfil>/DevToolsActivePort (o Chromium do PC abre com --remote-debugging-port=0). Só biblioteca padrão.

  pc ui --as <perfil>                 elementos interativos visíveis, numerados: [12] botão "Comprar"
  pc press --as <perfil> N            clica no elemento N (eventos de mouse reais, depois de rolar até ele)
  pc set --as <perfil> N "texto"      escreve no campo N (substitui o que havia); num <select>, escolhe a opção
"""
import base64, json, os, socket, struct, sys, time, urllib.request

LIMIT = 120  # elementos por leitura: o resto fica para depois de rolar

SNAPSHOT = r"""
(() => {
  for (const e of document.querySelectorAll('[data-pc-id]')) e.removeAttribute('data-pc-id');
  const W = innerWidth, H = innerHeight, out = [];
  const visible = e => {
    const r = e.getBoundingClientRect();
    if (r.width < 2 || r.height < 2 || r.bottom < 0 || r.right < 0 || r.top > H || r.left > W) return false;
    const s = getComputedStyle(e);
    return s.visibility !== 'hidden' && s.display !== 'none' && +s.opacity > 0.05;
  };
  const clean = t => (t || '').replace(/\s+/g, ' ').trim().slice(0, 80);
  // O nome que a pessoa vê: aria-label, o <label> do campo, o texto, o placeholder… o atributo name só por último.
  const label = e => clean(e.getAttribute('aria-label') || (e.labels && e.labels[0] && e.labels[0].innerText) ||
                           e.innerText || e.placeholder || e.title || e.alt || (e.type === 'submit' ? e.value : '') ||
                           e.getAttribute('name'));
  const kind = e => {
    const t = e.tagName.toLowerCase(), role = e.getAttribute('role'), type = (e.type || '').toLowerCase();
    if (t === 'a') return 'link';
    if (t === 'select') return 'menu';
    if (t === 'textarea' || e.isContentEditable) return 'campo';
    if (t === 'input') {
      if (type === 'checkbox') return e.checked ? 'caixa [x]' : 'caixa [ ]';
      if (type === 'radio') return e.checked ? 'opção (•)' : 'opção ( )';
      if (['submit', 'button', 'reset'].includes(type)) return 'botão';
      return 'campo' + (type && type !== 'text' ? ' ' + type : '');
    }
    if (t === 'button' || role === 'button') return 'botão';
    return role || 'clicável';
  };
  const sel = 'a[href], button, input:not([type=hidden]), select, textarea, [role=button], [role=link], [role=tab], ' +
              '[role=menuitem], [role=checkbox], [role=option], [onclick], [contenteditable=true], summary';
  let n = 0, more = 0;
  for (const e of document.querySelectorAll(sel + ', h1, h2, h3')) {
    if (!visible(e) || e.disabled) continue;
    if (/^H[123]$/.test(e.tagName)) { const t = clean(e.innerText); if (t) out.push('# ' + t); continue; }
    if (n >= __LIMIT__) { more++; continue; }
    e.setAttribute('data-pc-id', ++n);
    let line = '[' + n + '] ' + kind(e) + ' "' + label(e) + '"';
    if (e.tagName === 'SELECT') line += ' = "' + clean(e.options[e.selectedIndex]?.text) + '"';
    else if ((e.tagName === 'INPUT' || e.tagName === 'TEXTAREA') && !['checkbox', 'radio', 'submit', 'button'].includes(e.type) && e.value)
      line += ' = "' + (e.type === 'password' ? '••••' : clean(e.value)) + '"';
    out.push(line);
  }
  const below = document.documentElement.scrollHeight - scrollY - H;
  return [document.title + ' — ' + location.href, ...out,
          more ? '(+' + more + ' elementos visíveis além do limite)' : '',
          below > 40 ? '(a página continua para baixo: company pc scroll para ver mais e company pc ui de novo)' : ''].filter(Boolean).join('\n');
})()
""".replace("__LIMIT__", str(LIMIT))


class CDP:
    """Cliente WebSocket mínimo (RFC 6455) para uma aba do Chromium."""

    def __init__(self, ws_url):
        host, _, path = ws_url[len("ws://"):].partition("/")
        h, _, p = host.partition(":")
        self.s = socket.create_connection((h, int(p)), timeout=15)
        key = base64.b64encode(os.urandom(16)).decode()
        self.s.sendall((f"GET /{path} HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                        f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
        head = b""
        while b"\r\n\r\n" not in head:
            head += self.s.recv(1)
        if b" 101 " not in head.split(b"\r\n")[0]:
            raise SystemExit("o Chromium recusou a conexão de depuração")
        self.n = 0

    def _send(self, text):
        data = text.encode()
        mask = os.urandom(4)
        n = len(data)
        head = bytes([0x81]) + (bytes([0x80 | n]) if n < 126 else bytes([0x80 | 126]) + struct.pack(">H", n) if n < 65536
                                else bytes([0x80 | 127]) + struct.pack(">Q", n))
        self.s.sendall(head + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

    def _exact(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.s.recv(n - len(buf))
            if not chunk:
                raise SystemExit("a conexão com o Chromium caiu")
            buf += chunk
        return buf

    def _recv(self):
        msg = b""
        while True:
            b0, b1 = self._exact(2)
            n = b1 & 0x7F
            if n == 126:
                n = struct.unpack(">H", self._exact(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", self._exact(8))[0]
            msg += self._exact(n)
            if b0 & 0x80:
                return msg.decode()

    def call(self, method, **params):
        self.n += 1
        self._send(json.dumps({"id": self.n, "method": method, "params": params}))
        while True:
            m = json.loads(self._recv())
            if m.get("id") == self.n:
                if "error" in m:
                    raise SystemExit(m["error"].get("message", "erro do Chromium"))
                return m.get("result", {})

    def js(self, expr):
        r = self.call("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True)
        if "exceptionDetails" in r:
            raise SystemExit("erro na página: " + r["exceptionDetails"].get("text", ""))
        return r.get("result", {}).get("value")


def tab(profile):
    d = os.path.expanduser(f"~/.config/chromium-bots/{profile}")
    try:
        port = open(os.path.join(d, "DevToolsActivePort")).readline().strip()
        pages = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list", timeout=5))
    except (OSError, ValueError):
        raise SystemExit("o navegador deste bot não está aberto (ou abriu antes de suportar isto): use company pc open <url>")
    pages = [p for p in pages if p.get("type") == "page" and not p.get("url", "").startswith("chrome-extension://")]
    if not pages:
        raise SystemExit("nenhuma aba aberta: use company pc open <url>")
    return CDP(pages[0]["webSocketDebuggerUrl"])  # a aba ativa vem primeiro


def center(c, n):
    r = c.js(f"""(() => {{ const e = document.querySelector('[data-pc-id="{int(n)}"]');
      if (!e) return null; e.scrollIntoView({{block: 'nearest', inline: 'nearest'}});
      const r = e.getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2, e.tagName]; }})()""")
    if not r:
        raise SystemExit(f"não achei o elemento {n}: a página mudou? rode company pc ui de novo")
    return r


def press(c, n):
    x, y, tag = center(c, n)
    for t in ("mouseMoved", "mousePressed", "mouseReleased"):
        c.call("Input.dispatchMouseEvent", type=t, x=x, y=y, button="left", clickCount=1)
    return tag


def main():
    a = sys.argv[1:]
    if len(a) < 3 or a[1] != "--as":
        raise SystemExit(__doc__)
    action, profile, rest = a[0], a[2], a[3:]
    if action == "ui":
        # Logo depois de um pc open o navegador ainda está abrindo, ou a aba em about:blank/carregando: espera até 10 s.
        for _ in range(20):
            try:
                c = tab(profile)
                if c.js("location.href !== 'about:blank' && document.readyState === 'complete'"):
                    break
            except SystemExit:
                pass
            time.sleep(0.5)
        print(tab(profile).js(SNAPSHOT))
        return
    c = tab(profile)
    if action == "press" and rest:
        press(c, rest[0])
        print("ok")
    elif action == "set" and len(rest) >= 2:
        n, text = rest[0], " ".join(rest[1:])
        x, y, tag = center(c, n)
        if tag == "SELECT":
            ok = c.js(f"""(() => {{ const e = document.querySelector('[data-pc-id="{int(n)}"]'), t = {json.dumps(text)}.toLowerCase();
              const o = [...e.options].find(o => o.text.trim().toLowerCase() === t || o.value.toLowerCase() === t)
                     || [...e.options].find(o => o.text.toLowerCase().includes(t));
              if (!o) return false; e.value = o.value;
              e.dispatchEvent(new Event('input', {{bubbles: true}})); e.dispatchEvent(new Event('change', {{bubbles: true}})); return true; }})()""")
            if not ok:
                raise SystemExit(f'não há a opção "{text}" no menu {n}')
        else:
            press(c, n)
            c.js(f"""(() => {{ const e = document.querySelector('[data-pc-id="{int(n)}"]');
              if (e.select) e.select(); else document.execCommand('selectAll'); }})()""")
            c.call("Input.insertText", text=text)
        print("ok")
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
