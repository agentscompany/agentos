# syntax=docker/dockerfile:1
# AgentOS: o PC dos bots da AgentsCompany. Debian 13 mínimo com desktop, visto pelo app via noVNC.
# Publicado como ghcr.io/agentscompany/agentos:<versão> (arm64 + amd64). Contrato com o daemon: README.md.
FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8 TZ=America/Sao_Paulo

RUN apt-get update && apt-get install -y --no-install-recommends \
      tigervnc-standalone-server tigervnc-tools openbox picom hsetroot xdotool scrot \
      chromium xfce4-terminal thunar websockify dbus-x11 xdg-utils socat \
      fonts-noto-color-emoji fonts-noto-cjk \
      sudo curl ca-certificates git python3 procps less nano unzip xz-utils tzdata \
 && rm -rf /var/lib/apt/lists/*

# noVNC como arquivos estáticos (o pacote do Debian puxaria o Node.js inteiro).
RUN mkdir -p /usr/share/novnc \
 && curl -fsSL https://github.com/novnc/noVNC/archive/refs/tags/v1.6.0.tar.gz | tar xz --strip-components=1 -C /usr/share/novnc

# Os CLIs dos bots (Claude Code, Codex, Grok, opencode, Cursor) não vêm na imagem: o app instala sob demanda,
# na home (volume ac-home), com os instaladores oficiais. Sobrevivem à recriação do PC e se atualizam sozinhos.
ENV PATH=/home/ac/.local/bin:/home/ac/.grok/bin:/home/ac/.opencode/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Usuário dos bots, com sudo sem senha. O uid vira o do dono das pastas montadas na partida (AC_UID):
# assim a mesma imagem pronta serve no Mac (501) e no Linux (1000).
RUN useradd -m -u 1000 -s /bin/bash ac && echo 'ac ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ac

# Chromium dentro de container: sem sandbox do Chrome, sem telas de boas-vindas; depuração (CDP) numa porta
# aleatória só dentro do PC, anotada em <perfil>/DevToolsActivePort (o `pc ui` lê a página por ela); câmera e
# microfone aceitos sem perguntar (o PC não tem nenhum: o Meet entra com os dois desligados em vez de travar no aviso).
COPY <<'EOF' /etc/chromium.d/agentscompany
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --no-sandbox --test-type --no-first-run --no-default-browser-check --disable-dev-shm-usage --password-store=basic --hide-crash-restore-bubble --remote-debugging-port=0 --use-fake-ui-for-media-stream"
EOF

# Desktop de verdade: janelas com barra de título escura (minimizar/maximizar/fechar), abrindo
# centralizadas num tamanho bom; o wallpaper aparece em volta. Tema próprio do openbox (botões nativos dele).
RUN sed -i 's#<name>Clearlooks</name>#<name>AgentsCompany</name>#' /etc/xdg/openbox/rc.xml \
 && sed -i 's#<keepBorder>yes</keepBorder>#<keepBorder>no</keepBorder>#' /etc/xdg/openbox/rc.xml \
 && sed -i 's#</applications>#<application class="Chromium*"><position force="yes"><x>center</x><y>36</y></position><size><width>92%</width><height>81%</height></size></application><application class="Xfce4-terminal"><position force="yes"><x>center</x><y>center</y></position><size><width>780</width><height>480</height></size></application><application class="Thunar"><position force="yes"><x>center</x><y>center</y></position><size><width>900</width><height>560</height></size></application></applications>#' /etc/xdg/openbox/rc.xml

COPY <<'EOF' /usr/share/themes/AgentsCompany/openbox-3/themerc
border.width: 0
padding.width: 10
padding.height: 7
window.handle.width: 0
window.client.padding.width: 0
window.client.padding.height: 0
window.label.text.justify: center
window.active.title.bg: flat solid
window.active.title.bg.color: #f4f4f6
window.inactive.title.bg: flat solid
window.inactive.title.bg.color: #ececef
window.active.label.bg: parentrelative
window.inactive.label.bg: parentrelative
window.active.label.text.color: #1c1c1e
window.inactive.label.text.color: #8e8e93
window.active.button.unpressed.bg: parentrelative
window.active.button.unpressed.image.color: #5a5a5f
window.active.button.hover.bg: flat solid
window.active.button.hover.bg.color: #e2e2e6
window.active.button.hover.image.color: #1c1c1e
window.active.button.pressed.bg: flat solid
window.active.button.pressed.bg.color: #d4d4d9
window.active.button.pressed.image.color: #1c1c1e
window.active.button.disabled.bg: parentrelative
window.active.button.disabled.image.color: #b0b0b5
window.active.button.toggled.unpressed.bg: parentrelative
window.active.button.toggled.unpressed.image.color: #5a5a5f
window.inactive.button.unpressed.bg: parentrelative
window.inactive.button.unpressed.image.color: #a0a0a5
window.inactive.button.hover.bg: parentrelative
window.inactive.button.hover.image.color: #5a5a5f
window.inactive.button.pressed.bg: parentrelative
window.inactive.button.pressed.image.color: #5a5a5f
window.inactive.button.disabled.bg: parentrelative
window.inactive.button.disabled.image.color: #c8c8cc
window.inactive.button.toggled.unpressed.bg: parentrelative
window.inactive.button.toggled.unpressed.image.color: #a0a0a5
menu.border.width: 0
menu.items.bg: flat solid
menu.items.bg.color: #f4f4f6
menu.items.text.color: #1c1c1e
menu.items.disabled.text.color: #a0a0a5
menu.items.active.bg: flat solid
menu.items.active.bg.color: #3b82f6
menu.items.active.text.color: #ffffff
menu.title.bg: flat solid
menu.title.bg.color: #ececef
menu.title.text.color: #1c1c1e
menu.separator.color: #dcdce0
osd.bg: flat solid
osd.bg.color: #f4f4f6
osd.label.text.color: #1c1c1e
EOF

# Chromium limpo: sem convite de login/sincronização e sem pedir para ser o navegador padrão.
# Cada bot abre o próprio perfil, com a cor dele (ver `pc open --as`).
COPY <<'EOF' /etc/chromium/policies/managed/agentscompany.json
{"BrowserSignin": 0, "SyncDisabled": true, "PromotionsEnabled": false, "DefaultBrowserSettingEnabled": false}
EOF

COPY <<'EOF' /etc/xdg/picom.conf
backend = "xrender";
shadow = true;
shadow-radius = 18;
shadow-opacity = 0.35;
shadow-offset-x = -14;
shadow-offset-y = -10;
corner-radius = 10;
fading = true;
fade-delta = 6;
rounded-corners-exclude = [ "window_type = 'desktop'" ];
EOF

# Sobe o desktop: Xvnc (tela :1, 1280x800, com senha) + openbox + picom + wallpaper + noVNC na 6080.
# Partida (como root): ajusta o uid do ac ao dono das pastas montadas, arruma a home e sobe o desktop como ac.
COPY --chmod=755 <<'EOF' /usr/local/bin/pc-start
#!/bin/sh
if [ -n "$AC_UID" ] && [ "$(id -u ac)" != "$AC_UID" ]; then usermod -u "$AC_UID" ac; fi
# Home num volume novo: o container da Apple não copia a home da imagem (nasce vazia e do root).
chown ac:ac /home/ac
[ -f /home/ac/.profile ] || runuser -u ac -- cp -rn /etc/skel/. /home/ac/
exec runuser -u ac -- pc-desktop
EOF

COPY --chmod=755 <<'EOF' /usr/local/bin/pc-desktop
#!/bin/sh
mkdir -p "$HOME/.vnc"
printf '%s\n' "${VNC_PW:-agents}" | vncpasswd -f > "$HOME/.vnc/passwd"
chmod 600 "$HOME/.vnc/passwd"
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
Xvnc :1 -geometry 1280x800 -depth 24 -rfbport 5901 -localhost -AlwaysShared -SecurityTypes VncAuth -PasswordFile "$HOME/.vnc/passwd" &
export DISPLAY=:1
for i in 1 2 3 4 5 6 7 8 9 10; do [ -e /tmp/.X11-unix/X1 ] && break; sleep 0.3; done
hsetroot -solid "${AC_TINT:-#d6d6db}"   # cor lisa; o app troca para a cor do bot (pc tint)
openbox &
picom -b
exec websockify --web /usr/share/novnc 0.0.0.0:6080 localhost:5901
EOF

# Logins dos CLIs: o link abre no navegador do Mac (o app repassa o retorno do OAuth para cá).
# Fora do login (sem AC_OPEN_URL) ou se o app recusar, abre no Chromium do PC como sempre.
COPY --chmod=755 <<'EOF' /usr/local/bin/xdg-open
#!/bin/sh
if [ -n "$AC_OPEN_URL" ] && curl -sS --fail -H 'Expect:' --data-binary "$1" "$AC_OPEN_URL" >/dev/null 2>&1; then exit 0; fi
exec /usr/bin/xdg-open "$@"
EOF

# Ações na tela, usadas pelo app (`company pc …`).
COPY --chmod=755 <<'EOF' /usr/local/bin/pc
#!/bin/sh
export DISPLAY=:1
case "$1" in
  screenshot) f="${2:-/tmp/screen.png}"; scrot -o -p "$f" && echo "$f" ;;
  click)  xdotool mousemove "$2" "$3" click "${4:-1}" ;;
  double) xdotool mousemove "$2" "$3" click --repeat 2 1 ;;
  move)   xdotool mousemove "$2" "$3" ;;
  type)   shift; xdotool type --delay 12 -- "$*" ;;
  key)    shift; xdotool key -- "$@" ;;
  scroll) n="${4:-3}"; b=5; if [ "$n" -lt 0 ]; then b=4; n=$((-n)); fi; xdotool mousemove "$2" "$3" click --repeat "$n" "$b" ;;
  tint)   hsetroot -solid "$2" ;;
  open)   shift
          # --as <perfil> <#rrggbb>: Chromium no perfil do bot, com um tema completo gerado da cor dele
          # (moldura, abas, barra, campo de endereço e nova aba), carregado como extensão de tema.
          if [ "$1" = "--as" ]; then
            d="$HOME/.config/chromium-bots/$2"; color="$3"; shift 3
            mkdir -p "$d/Default" "$d/theme"
            python3 - "$d/theme/manifest.json" "$color" <<'PY'
import json, sys
path, hexc = sys.argv[1], sys.argv[2].lstrip("#")
base = [int(hexc[i:i + 2], 16) for i in (0, 2, 4)]
def mix(c, t, f): return [round(c[i] + (t[i] - c[i]) * f) for i in range(3)]
white, black, ink = [255, 255, 255], [0, 0, 0], [30, 30, 32]
lum = (0.299 * base[0] + 0.587 * base[1] + 0.114 * base[2]) / 255
on_frame = ink if lum > 0.6 else white          # texto das abas inativas legível em cores escuras
colors = {
    "frame": mix(base, white, 0.1), "frame_inactive": mix(base, white, 0.3),
    "toolbar": mix(base, white, 0.7), "toolbar_button_icon": mix(base, black, 0.5),
    "tab_text": ink, "tab_background_text": on_frame, "tab_background_text_inactive": on_frame,
    "omnibox_background": mix(base, white, 0.85), "omnibox_text": ink, "bookmark_text": ink,
    "ntp_background": mix(base, white, 0.65), "ntp_text": ink, "ntp_link": mix(base, black, 0.4),
}
manifest = {"manifest_version": 3, "name": "AgentsCompany", "version": "1." + str(int(hexc, 16)),
            "theme": {"colors": colors}}
json.dump(manifest, open(path, "w"))
PY
            # O tema entra num processo ainda sem janela: assim o aviso "Installed theme" não tem onde aparecer
            # (com --load-extension o Chromium reinstala o tema a cada processo novo).
            if ! pgrep -f -- "--user-data-dir=$d( |$)" >/dev/null; then
              setsid chromium --no-startup-window --user-data-dir="$d" --load-extension="$d/theme" >/dev/null 2>&1 &
              for i in 1 2 3 4 5 6 7 8 9 10; do [ -e "$d/SingletonSocket" ] && break; sleep 0.3; done; sleep 1
            fi
            setsid chromium --user-data-dir="$d" ${1:+"$1"} >/dev/null 2>&1 &
            exit 0
          fi
          case "$1" in
            terminal) shift; setsid xfce4-terminal --hide-menubar --hide-toolbar --hide-scrollbar "$@" >/dev/null 2>&1 & ;;
            files)    setsid thunar >/dev/null 2>&1 & ;;
            ""|browser|chromium) setsid chromium >/dev/null 2>&1 & ;;
            *)        setsid chromium "$1" >/dev/null 2>&1 & ;;
          esac ;;
  ui|press|set|text|upload) exec pc-ui "$@" ;;   # a página em texto e ações pelo número do elemento (pc-ui)
  *) echo "uso: pc ui | press N | set N texto | text | upload N arquivo | screenshot [arquivo] | click X Y | double X Y | type texto | key ctrl+l | scroll X Y N | open url|terminal|files" >&2; exit 2 ;;
esac
EOF

COPY --chmod=755 pc-ui.py /usr/local/bin/pc-ui

WORKDIR /home/ac
ENV HOME=/home/ac
EXPOSE 6080
CMD ["pc-start"]
