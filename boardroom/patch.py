#!/usr/bin/env python3
"""Build app/ from the pinned upstream copy of arscan/encom-boardroom (MIT).

Upstream's "Test Stream" folder becomes a SYSTEM stream fed by server.py with
real events from this machine, instead of generating random test data. The
2014 Grunt/Browserify toolchain does not run on current Node, so the edits are
made to the prebuilt bundle. Every edit asserts it matched exactly once, so a
different upstream fails loudly rather than half-patching.

Re-run after changing this file:  python3 patch.py
"""
import pathlib
import re
import shutil
import sys

HERE = pathlib.Path(__file__).resolve().parent
UPSTREAM = HERE / "upstream"
APP = HERE / "app"


def edit(text, old, new, count=1, what=""):
    found = text.count(old)
    if found != count:
        sys.exit(f"patch failed ({what or old[:60]!r}): expected {count} match(es), found {found}")
    return text.replace(old, new)


def patch_bundle(js):
    # ── main.js: the "test" view becomes the SYSTEM stream ────────────────
    js = edit(js, '$("#screensaver").text("TEST DATA");',
              '$("#screensaver").text("SYSTEM");', what="splash text")
    js = edit(js, 'Boardroom.init("test");',
              'Boardroom.init("system", window.encomSystemHistory);', what="init")

    start = js.index("        /* lets just throw some data in there */")
    end = js.index("        }, 800);", start) + len("        }, 800);")
    js = js[:start] + "        /* ENCOM: events arrive from server.py over /events.js */" + js[end:]

    # ── LightTable fake terminal: show "system" instead of "test" ─────────
    js = edit(js, 'simulateCommand("|cd test$");', 'simulateCommand("|cd system$");')
    js = edit(js, 'simulateCommand("run test.exe$");', 'simulateCommand("run system.exe$");')
    js = edit(js, "'<div class=\"ls ls-test\">test</div>',",
              "'<div class=\"ls ls-test\">system</div>',", what="ls listing")
    js = edit(js, 'command == "run test.exe"', 'command == "run system.exe"')
    js = edit(js, 'if(currentDir == "test"){', 'if(currentDir == "system"){')
    js = edit(js, 'command == "cd test"', 'command == "cd system"')
    js = edit(js, 'currentDir = "test";', 'currentDir = "system";')
    js = edit(js, "Changed directory to <span class='highlight'>test</span>",
              "Changed directory to <span class='highlight'>system</span>")

    # ── Chart captions: derive quarter and year from the data ─────────────
    # Upstream hard-codes "2013" and assumes frames start on 1 January. The
    # GitHub replay still reads "1st Quarter 2013"; SYSTEM gets its own dates.
    js = edit(js, "    var frameData = [];\n\n    for (var i = 0; i< this.opts.data.length; i++){",
              "    var frameData = [];\n"
              "    var frameStart = 0;\n"
              "    var encomQuarter = function(d){\n"
              "        if(!d || !d.year){ return \"Recent\"; }\n"
              "        return [\"1st\", \"2nd\", \"3rd\", \"4th\"][Math.floor((d.month - 1) / 3)] + \" Quarter \" + d.year;\n"
              "    };\n\n"
              "    for (var i = 0; i< this.opts.data.length; i++){", what="chart loop head")
    js = edit(js, 'this.addFrame(quarter + " 2013 Activity"',
              'this.addFrame(encomQuarter(this.opts.data[frameStart]) + " Activity"',
              count=2, what="chart captions")
    js = edit(js, "            frameData = [];\n            if(q == 0){",
              "            frameData = [];\n            frameStart = i;\n            if(q == 0){",
              what="frame start")
    js = edit(js, "        $(\"#ticker-value\").text(formatYTD(data[0].events, data[data.length-1].events));",
              "        $(\"#ticker-value\").text(formatYTD(data[0].events, data[data.length-1].events));\n"
              "        $(\"#ticker-ytd\").text(data[data.length-1].year + \" Events\");",
              what="ticker year")
    # ── Keep events that arrive during the terminal intro ─────────────────
    # Upstream hands every message to the light table until a stream is
    # running, and the light table ignores all but link status -- so the
    # startup burst (existing connections, active alerts) was thrown away on
    # every page load. Hold those, then replay them once the boardroom is up.
    js = edit(js, 'var active = "lt";',
              'var active = "lt";\n'
              'var encomBacklog = [];\n'
              'var encomFlush = function(){\n'
              '    var queued = encomBacklog;\n'
              '    encomBacklog = [];\n'
              '    queued.forEach(function(m, i){\n'
              '        setTimeout(function(){ Boardroom.message(m); }, 1500 + i * 300);\n'
              '    });\n'
              '};', what="backlog decl")
    js = edit(js, '        if(active === "lt"){\n'
                  '            LightTable.message(JSON.parse(event.data));\n'
                  '        } else {',
              '        if(active === "lt"){\n'
              '            var encomMsg = JSON.parse(event.data);\n'
              '            LightTable.message(encomMsg);\n'
              '            if(encomMsg.stream !== "meta" && encomBacklog.length < 40){\n'
              '                encomBacklog.push(encomMsg);\n'
              '            }\n'
              '        } else {', what="backlog capture")
    js = edit(js, '            active = "br";\n            Boardroom.show();',
              '            active = "br";\n            Boardroom.show();\n            encomFlush();',
              count=3, what="backlog flush")

    # ── Live list: flag alert rows (orange, with the "!" marker) and
    # RESOLVED rows (green). The <ul> is reused as rows rotate, so its class
    # is reset on every message.
    js = edit(js, "        if(message.popularity > 100){",
              "        lastChild.className = \"interaction-data\" + (message.alert ? \" encom-alert\" : "
              "(message.type === \"OK\" ? \" encom-ok\" : \"\"));\n"
              "        if(message.popularity > 100 || message.alert){", what="alert rows")

    # ── The stopwatch and its dial count from this machine's boot (from
    # server.py, window.encomBootTime) instead of from page load, so every
    # new Boardroom shows the same running time. Hours no longer wrap at 100.
    js = edit(js, "    var elapsed = new Date() - startDate;",
              "    var elapsed = new Date() - (window.encomBootTime || startDate);", what="stopwatch")
    js = edit(js, "    var hours = Math.floor((elapsed / 3600000) % 100); ",
              "    var hours = Math.floor(elapsed / 3600000); ", what="stopwatch hours")
    js = edit(js, "SimpleClock.prototype.tick = function(){\n"
                  "    var timeSinceStarted = new Date() - this.firstTick;",
              "SimpleClock.prototype.tick = function(){\n"
              "    var timeSinceStarted = new Date() - (window.encomBootTime || this.firstTick);",
              what="stopwatch dial")
    # ── Theme colours ─────────────────────────────────────────────────────
    # The app draws its canvases (globe, charts, dials) in its own cyan and
    # amber. Look them up at run time instead, so they follow the current
    # theme (window.encomColour comes from the server's /palette.js, which
    # loads first; unthemed, it hands back the same colour).
    for base in ("#00eeee", "#ffcc00", "#8fd8d8"):
        # The bundle spells them in both cases.
        literal = re.compile('"' + re.escape(base) + '"', re.IGNORECASE)
        if not literal.search(js):
            sys.exit("colour %s not found in the bundle" % base)
        js = literal.sub(lambda m: "window.encomColour(%s)" % m.group(0), js)
    js = ("window.encomColour = window.encomColour || function (c) { return c };\n") + js

    return js


def patch_html(html):
    html = edit(html, "                    TIME SINCE START\n",
                "                    TIME SINCE BOOT\n", what="stopwatch label")
    html = edit(html, """                                <div class="folder-label">
                                    Test Stream
                                </div>""",
                """                                <div class="folder-label">
                                    System
                                </div>""", what="folder label")

    # Boardroom.init looks up #boardroom-readme-<stream>.
    html = edit(html, 'id="boardroom-readme-test"', 'id="boardroom-readme-system"')
    html = edit(html, "TEST STREAM INFO", "SYSTEM STREAM INFO")
    html = edit(html,
                "You've probably already figured this out, but the data being streamed here is just test data.",
                "Live events from this machine: network connections placed by an offline IP "
                "database, windows opening, journal warnings, logins and hardware changes. "
                "The historic chart is daily journal activity since install.",
                what="readme text")

    html = edit(html, '<link href="css/boardroom-styles.css" rel="stylesheet" type="text/css" />',
                '<link href="css/boardroom-styles.css" rel="stylesheet" type="text/css" />\n'
                '        <link href="encom-local.css" rel="stylesheet" type="text/css" />',
                what="local stylesheet")

    # Streams with real history (GitHub, SYSTEM) set this from their data;
    # Wikipedia has none and upstream fills its chart with random placeholder
    # data, so the static default says so rather than claiming "2013".
    html = edit(html, """                        <div id="ticker-ytd">
                            2013 Events
                        </div>""", """                        <div id="ticker-ytd">
                            Placeholder
                        </div>""", what="ticker default")

    # History for the chart before the bundle; our glue after it.
    html = edit(html, '<script src="build/encom-boardroom.js"></script>',
                '<script src="history.js"></script>\n'
                '        <script src="palette.js"></script>\n'
                '        <script src="build/encom-boardroom.js"></script>\n'
                '        <script src="encom-local.js"></script>', what="script tags")
    return html


def main():
    if APP.exists():
        shutil.rmtree(APP)
    shutil.copytree(UPSTREAM, APP)

    bundle = APP / "build" / "encom-boardroom.js"
    bundle.write_text(patch_bundle(bundle.read_text()))
    index = APP / "index.html"
    index.write_text(patch_html(index.read_text()))
    shutil.copy(HERE / "encom-local.js", APP / "encom-local.js")
    shutil.copy(HERE / "encom-local.css", APP / "encom-local.css")
    shutil.copy(HERE / "assets" / "alert-portrait.gif", APP / "encom-portrait.gif")
    print("app/ built from upstream", (UPSTREAM / "UPSTREAM_REV").read_text().strip()[:12])


if __name__ == "__main__":
    main()
