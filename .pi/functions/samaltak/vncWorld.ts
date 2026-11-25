/** The operator's screen-shared World on a VNC server: by default the Linux appliance in QEMU (make linux-appliance-run: its data volume with samaltak.args, the control token and the VNC password; the image's own RFB server), or with target "uefi" the UEFI World (a samaltak-ctl --uefi session with --vnc); status (VM alive, VNC port, control, why it died), restart (keep the old log, stop, build, start, connect, send the agent and GitHub configs, optionally open Screen Sharing on the viewer's Mac), or close; dryRun shows the plan. */
async function vncWorld(
  { shell: { exec }, samaltak: { build, ctlSession, crashLog } },
  input: {
    target?: "appliance" | "uefi";
    action?: "status" | "restart" | "close";
    session?: string;
    display?: number;
    controlPort?: number;
    dir?: string;
    newData?: boolean;
    server?: "qemu" | "image";
    gpu?: string;
    windowSize?: string;
    affinity?: string;
    configs?: Array<"agent" | "github">;
    build?: boolean;
    viewerHost?: string;
    dryRun?: boolean;
  } = {},
) {
  // The World the operator watches over VNC, on 127.0.0.1:5900+display, with the VNC password of ~/.samaltak-vnc
  // (UEFI_VNC_PASSWORD names another file), so the viewer's saved password works for every target. It runs from the
  // current directory's build (the operator's is the main checkout).
  // target "appliance" (default; docs/linux-appliance.md): session "la-vnc", display 2, controlPort 17342, dir
  // /tmp/<session> (TMPDIR's). restart: copies dir/console.log aside, stops the appliance (samaltak-ctl close --quit:
  // the World's quit powers it off; else QMP system_powerdown; else the QEMU of dir/run.pid, which this function wrote),
  // builds (make linux-appliance, unless build: false), makes the data volume dir/data.img when there is none or with
  // newData (ext4 SAMALTAK-DATA: samaltak.args with control and RFB on every address, a new control token and the VNC
  // password, 0600; a data volume kept keeps the World's snapshots, /data/samaltak.image, and its token, dir/control-token),
  // starts make linux-appliance-run in the background (LINUX_RFB_PORT, LINUX_CONTROL_PORT, LINUX_DATA, LINUX_QMP; the
  // console in dir/console.log, the QEMU's PID in dir/run.pid), connects the session (samaltak-ctl connect with the
  // token file) and sends the configs. windowSize applies to SDL's variants (on the virtio variant's KMS screen the
  // display's mode is the World's size).
  // target "uefi" (docs/uefi.md): session "vnc", display 1: tools/samaltak-ctl --session <session> open --uefi
  // --window-size WxH --vnc <display> --vnc-server <server>; server "image" (default) the image's own RFB server
  // (UEFI_DISPLAY), "qemu" QEMU's VNC server (UEFI_VNC); UEFI_GPU=<gpu> (virtio-gpu-pci: 1920x1080; ramfb stops at
  // 1024x768); affinity: QEMU's host CPUs (UEFI_AFFINITY, tools/qemu-pin.sh: "big", a taskset list, "none"). restart
  // copies the session's log aside, closes it, builds (samaltak.build all), opens it again (keepOpen) and sends the configs.
  // Both: configs ["agent", "github"] (agent-config --from-pi: pi's API key, maybe through 1Password, which the operator
  // may have to approve; github-config --from-gh); viewerHost (an ssh host, e.g. the operator's Mac, with a LocalForward
  // of the port to this machine) runs open "vnc://:<its ~/.samaltak-vnc>@localhost:<port>" there: the password is read
  // on that host and never printed. status (default): alive, listening (an RFB greeting on the port), the control
  // service, and for a dead VM its log's triage. close: stops it (its log kept aside first).
  // The operator's live Worlds (la-vnc on 5902, vnc on 5901): restart them only when asked; try things on another
  // session, display and control port (e.g. { session: "la-test", display: 7, controlPort: 17349 }).
  const target = input.target ?? "appliance";
  if (target !== "appliance" && target !== "uefi") throw new Error('vncWorld: target is "appliance" or "uefi"');
  const action = input.action ?? "status";
  const session = input.session ?? (target === "appliance" ? "la-vnc" : "vnc");
  if (!/^[A-Za-z0-9_-]+$/.test(session)) throw new Error("vncWorld: bad session name");
  const display = input.display ?? (target === "appliance" ? 2 : 1);
  if (!Number.isInteger(display) || display < 0 || display > 99)
    throw new Error("vncWorld: display is 0-99");
  const port = 5900 + display;
  const controlPort = input.controlPort ?? 17342;
  if (!Number.isInteger(controlPort) || controlPort < 1024 || controlPort > 65535 || controlPort === port)
    throw new Error("vncWorld: controlPort is 1024-65535, not the VNC port");
  const server = input.server ?? "image";
  if (server !== "qemu" && server !== "image") throw new Error('vncWorld: server is "qemu" or "image"');
  const gpu = input.gpu ?? "virtio-gpu-pci";
  const windowSize = input.windowSize ?? "1920x1080";
  if (!/^[A-Za-z0-9_-]+$/.test(gpu) || !/^\d+x\d+$/.test(windowSize))
    throw new Error("vncWorld: bad gpu or windowSize");
  const affinity = input.affinity ?? "big";
  if (!/^(big|none|[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*)$/.test(affinity))
    throw new Error("vncWorld: affinity is big, none or a CPU list");
  const configs = input.configs ?? ["agent", "github"];
  if (input.viewerHost && !/^[A-Za-z0-9_.@-]+$/.test(input.viewerHost))
    throw new Error("vncWorld: bad viewerHost");
  const tmp = (await exec('printf %s "${TMPDIR:-/tmp}"')).stdout.replace(/\/+$/, "");
  const dir = input.dir ?? tmp + "/" + session;
  if (!/^\/[A-Za-z0-9_.\/-]+$/.test(dir) || dir.includes("..")) throw new Error("vncWorld: dir is an absolute path");
  const q = (s: string) => "'" + s.replace(/'/g, "") + "'";
  // QEMU's hostfwd listens before the image's server does: ready is the server's RFB version greeting.
  const greets = async (p: number) =>
    (
      await exec(
        "timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/" + p + " && head -c 4 <&3' 2>/dev/null | grep -q '^RFB'",
      )
    ).code === 0;
  const portFree = async (p: number) =>
    (await exec("timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/" + p + "' 2>/dev/null")).code !== 0;
  const listening = () => greets(port);
  const ctl = (args: string, timeoutMs = 20000) =>
    exec("tools/samaltak-ctl --session " + session + " " + args + " </dev/null 2>&1", { timeoutMs });
  const pwFile = (await exec('printf %s "${UEFI_VNC_PASSWORD:-$HOME/.samaltak-vnc}"')).stdout;
  const pw = (await exec("test -s " + q(pwFile))).code === 0;
  const steps: string[][] = [];
  if (configs.includes("agent")) steps.push(["agent-config", "--from-pi"]);
  if (configs.includes("github")) steps.push(["github-config", "--from-gh"]);
  const stamp = async () => (await exec("date +%Y%m%d-%H%M%S")).stdout.trim();
  const openViewer = async (up: boolean) => {
    if (!input.viewerHost || !up) return undefined;
    const v = await exec(
      "ssh -o BatchMode=yes -o ConnectTimeout=10 " + input.viewerHost +
        " 'p=$(cat ~/.samaltak-vnc 2>/dev/null) || { echo \"no ~/.samaltak-vnc there\"; exit 1; }; open \"vnc://:$p@localhost:" + port + "\" && echo \"Screen Sharing opened\"' 2>&1",
      { timeoutMs: 30000 },
    );
    return v.stdout.trim().split("\n").pop();
  };
  const stepLines = (results: Array<{ step: string[]; code: number | null; out: string; hint?: string }>) =>
    results.map(
      (r) =>
        r.step.join(" ") + ": " +
        (r.code === 0 ? "ok " + r.out.slice(0, 80) : "exit " + r.code + " " + r.out.slice(-200)) + (r.hint ? " (" + r.hint + ")" : ""),
    );

  if (target === "appliance") {
    // The appliance's QEMU: dir/run.pid's, if that process is still a QEMU with this data volume.
    const qemuPid = async () => {
      const r = await exec(
        "p=$(cat " + q(dir + "/run.pid") + " 2>/dev/null) && [ -n \"$p\" ] && tr '\\0' ' ' < /proc/$p/cmdline 2>/dev/null | grep -qF " +
          q("file=" + dir + "/data.img") + " && echo $p",
      );
      const p = parseInt(r.stdout.trim(), 10);
      return Number.isInteger(p) && p > 1 ? p : undefined;
    };
    const consoleTail = async () =>
      (await exec("tail -n 12 " + q(dir + "/console.log") + " 2>/dev/null | grep -aiv 'token\\|password'")).stdout
        .trim().split("\n").filter((l) => l).slice(-8);
    const state = async () => {
      const pid = await qemuPid();
      const ping = pid ? await ctl("eval '3 + 4'", 10000) : undefined;
      return {
        alive: pid !== undefined,
        pid,
        listening: await listening(),
        control: ping ? (ping.code === 0 && ping.stdout.trim() === "7" ? "ok" : ping.stdout.trim().split("\n").pop()?.slice(0, 200)) : undefined,
        dataVolume: (await exec("test -f " + q(dir + "/data.img"))).code === 0,
        console: pid ? undefined : await consoleTail(),
      };
    };
    const keepLog = async () =>
      (
        await exec(
          "L=" + q(dir + "/console.log") + "; [ -s \"$L\" ] || exit 0; K=" + q(dir) + "/console-" + (await stamp()) +
            ".log; cp \"$L\" \"$K\" && echo \"$K\"",
        )
      ).stdout.trim() || undefined;
    const waitGone = async (pid: number, seconds: number) => {
      for (let i = 0; i < seconds; i++) {
        if ((await exec("kill -0 " + pid + " 2>/dev/null")).code !== 0) return true;
        await exec("sleep 1");
      }
      return false;
    };
    const stop = async () => {
      const pid = await qemuPid();
      const how: string[] = [];
      const c = await ctl("close --quit", 30000);
      how.push("close --quit: " + c.stdout.trim().split("\n").pop()?.slice(0, 120));
      if (pid && !(await waitGone(pid, 30))) {
        await exec("python3 tools/linux-appliance/qmp.py " + q(dir + "/qmp.sock") + " system_powerdown 2>&1", { timeoutMs: 10000 });
        how.push("QMP system_powerdown");
        if (!(await waitGone(pid, 20))) {
          await exec("kill " + pid);
          how.push("kill " + pid + " (dir/run.pid's QEMU)");
          await waitGone(pid, 10);
        }
      }
      return { wasRunning: pid !== undefined, how };
    };
    if (action === "status") return { target, action, session, port, controlPort, dir, ...(await state()) };
    if (input.dryRun) {
      const data = !input.newData && (await exec("test -f " + q(dir + "/data.img"))).code === 0;
      return {
        target,
        action,
        dryRun: true,
        session,
        port,
        controlPort,
        dir,
        now: await state(),
        plan: [
          "copy " + dir + "/console.log aside",
          "tools/samaltak-ctl --session " + session + " close --quit (then QMP system_powerdown, then kill dir/run.pid's QEMU)",
          ...(action === "restart"
            ? [
                ...((input.build ?? true) ? ["make linux-appliance"] : []),
                data
                  ? "keep " + dir + "/data.img (its snapshots, the token in " + dir + "/control-token, the VNC password)"
                  : "make " + dir + "/data.img: ext4 SAMALTAK-DATA with samaltak.args (--control --control-host 0.0.0.0 --control-port 7341 --control-token-file /data/control-token --display --display-host 0.0.0.0 --display-port 5900 --display-vnc-auth --display-password-file /data/vnc-password), a new control token and the VNC password of <password file>, 0600",
                "LINUX_RFB_PORT=" + port + " LINUX_CONTROL_PORT=" + controlPort + " LINUX_DATA=" + dir + "/data.img LINUX_QMP=" + dir + "/qmp.sock make linux-appliance-run > " + dir + "/console.log (its QEMU's PID in " + dir + "/run.pid)",
                "tools/samaltak-ctl --session " + session + " connect --port " + controlPort + " --token-file " + dir + "/control-token",
                ...steps.map((s) => s.join(" ")),
                "check 127.0.0.1:" + port + " greets",
                ...(input.viewerHost ? ["ssh " + input.viewerHost + " open vnc://:<password>@localhost:" + port] : []),
              ]
            : []),
        ],
        passwordFile: pw ? "present" : "missing: create ~/.samaltak-vnc (at most 8 characters, mode 600) first",
      };
    }
    const kept = await keepLog();
    const stopped = await stop();
    if (action === "close") return { target, action, session, keptLog: kept, stopped, listening: await listening() };
    if (!pw)
      throw new Error("vncWorld: no VNC password file (~/.samaltak-vnc or UEFI_VNC_PASSWORD): create one (at most 8 characters, mode 600)");
    for (const p of [port, controlPort])
      if (!(await portFree(p)))
        throw new Error("vncWorld: 127.0.0.1:" + p + " is still in use after stopping session " + session + ": another VM has it");
    let built: { ok: boolean; seconds: number; tail: string[] } | undefined;
    if (input.build ?? true) {
      const t0 = Date.now();
      const b = await exec("make linux-appliance 2>&1", { timeoutMs: 285000, maxLines: 4000, truncate: "tail" });
      built = { ok: b.code === 0, seconds: Math.round((Date.now() - t0) / 100) / 10, tail: b.stdout.trim().split("\n").slice(-6) };
      if (!built.ok)
        return { target, action, session, keptLog: kept, stopped, build: built, ok: false, reason: "build failed: the World was not started" };
    }
    const variant = (await exec("cat build/linux-appliance/variant 2>/dev/null")).stdout.trim() || "mesa";
    let madeData = false;
    if (input.newData || (await exec("test -f " + q(dir + "/data.img"))).code !== 0) {
      const size = variant === "virtio" ? "" : "--window-size " + windowSize + " ";
      const m = await exec(
        "set -e; D=" + q(dir) + "; mkdir -p \"$D\"; rm -rf \"$D/data\" \"$D/data.img\"; mkdir \"$D/data\"; umask 077; " +
          "head -c 24 /dev/urandom | base64 | tr -d '/+=\\n' > \"$D/control-token\"; cp \"$D/control-token\" \"$D/data/control-token\"; " +
          "head -n 1 " + q(pwFile) + " | tr -d ' \\t\\r\\n' > \"$D/data/vnc-password\"; " +
          "printf '%s\\n' --max-heap 2048 " + size + "--control --control-host 0.0.0.0 --control-port 7341 --control-token-file /data/control-token " +
          "--display --display-host 0.0.0.0 --display-port 5900 --display-vnc-auth --display-password-file /data/vnc-password > \"$D/data/samaltak.args\"; " +
          "truncate -s 1G \"$D/data.img\"; PATH=$PATH:/sbin:/usr/sbin mkfs.ext4 -q -F -L SAMALTAK-DATA -d \"$D/data\" \"$D/data.img\" 2>&1",
      );
      if (m.code !== 0) throw new Error("vncWorld: cannot make the data volume: " + m.stdout.slice(-300));
      madeData = true;
    } else if ((await exec("test -s " + q(dir + "/control-token"))).code !== 0)
      throw new Error("vncWorld: " + dir + "/data.img has no " + dir + "/control-token beside it: newData: true makes a new volume (its snapshots go)");
    const started = await exec(
      "umask 077 && LINUX_RFB_PORT=" + port + " LINUX_CONTROL_PORT=" + controlPort +
        " LINUX_DATA=" + q(dir + "/data.img") + " LINUX_QMP=" + q(dir + "/qmp.sock") +
        " setsid make -s linux-appliance-run > " + q(dir + "/console.log") + " 2>&1 < /dev/null & echo $!",
    );
    const makePid = parseInt(started.stdout.trim(), 10);
    // its QEMU: a descendant of the make started here (never found by name alone)
    let pid: number | undefined;
    for (let i = 0; i < 30 && !pid && Number.isInteger(makePid); i++) {
      const f = await exec(
        "for p in $(pgrep -P " + makePid + "; for c in $(pgrep -P " + makePid + "); do pgrep -P $c; done); do tr '\\0' ' ' < /proc/$p/cmdline 2>/dev/null | grep -q '^qemu-system' && echo $p; done | head -1",
      );
      const p = parseInt(f.stdout.trim(), 10);
      if (Number.isInteger(p)) pid = p;
      else await exec("sleep 1");
    }
    if (!pid)
      return { target, action, session, ok: false, keptLog: kept, stopped, build: built, reason: "no QEMU started", console: (await exec("tail -n 8 " + q(dir + "/console.log"))).stdout };
    await exec("umask 077; echo " + pid + " > " + q(dir + "/run.pid"));
    let connected = false;
    for (let i = 0; i < 45 && !connected; i++) {
      connected = (await ctl("connect --port " + controlPort + " --token-file " + q(dir + "/control-token"), 15000)).code === 0;
      if (!connected) await exec("sleep 2");
    }
    const s = connected && steps.length
      ? await ctlSession({ session, keepOpen: true, continueOnError: true, stepTimeoutS: 200, steps })
      : undefined;
    let up = false;
    for (let i = 0; i < 15 && !(up = await listening()); i++) await exec("sleep 2");
    return {
      target,
      action,
      ok: connected && (s ? s.ok : true) && up,
      session,
      port,
      controlPort,
      dir,
      pid,
      variant,
      dataVolume: madeData ? "made (a new token and the VNC password)" : "kept",
      connected,
      listening: up,
      keptLog: kept,
      stopped,
      build: built,
      steps: s ? stepLines(s.results) : [],
      viewer: await openViewer(up),
      hint: up && connected ? undefined : "see " + dir + "/console.log (vncWorld's status shows its tail once the VM is gone)",
    };
  }

  // target "uefi"
  const state = async () => {
    const log = await crashLog({ session, contextLines: 8, tailLines: 6 }).catch(() => null);
    return {
      alive: log ? log.alive : false,
      listening: await listening(),
      meta: log?.meta,
      triage:
        log && log.alive === false
          ? {
              fatal: log.fatal,
              exit: log.exit,
              around: log.around && { before: log.around.before.slice(-6), after: log.around.after.slice(0, 12) },
              tail: log.tail,
            }
          : undefined,
      log: log?.file,
    };
  };
  const keepLog = async () =>
    (
      await exec(
        "L=\"${TMPDIR:-/tmp}/samaltak-ctl/" + session + ".log\"; [ -s \"$L\" ] || exit 0; K=\"${TMPDIR:-/tmp}/samaltak-ctl/" + session + "-" + (await stamp()) + ".log\"; cp \"$L\" \"$K\" && echo \"$K\"",
      )
    ).stdout.trim() || undefined;
  const close = async () => (await ctl("close", 60000)).stdout.trim().slice(-300);
  if (action === "status") return { target, action, session, server, port, ...(await state()) };
  if (input.dryRun)
    return {
      target,
      action,
      dryRun: true,
      session,
      port,
      now: await state(),
      plan: [
        "copy the session's log aside",
        "tools/samaltak-ctl --session " + session + " close",
        ...(action === "restart"
          ? [
              ...((input.build ?? true) ? ['samaltak.build({ target: "all" })'] : []),
              "UEFI_GPU=" + gpu + " UEFI_AFFINITY=" + affinity + " tools/samaltak-ctl --session " + session + " open --uefi --window-size " + windowSize + " --vnc " + display + " --vnc-server " + server + " --vnc-password-file <password file>",
              ...steps.map((s) => s.join(" ")),
              "check 127.0.0.1:" + port + " greets",
              ...(input.viewerHost ? ["ssh " + input.viewerHost + " open vnc://:<password>@localhost:" + port] : []),
            ]
          : []),
      ],
      passwordFile: pw ? "present" : "missing: create ~/.samaltak-vnc (at most 8 characters, mode 600) first",
    };
  const kept = await keepLog();
  const closed = await close();
  if (action === "close") return { target, action, session, keptLog: kept, closed, listening: await listening() };
  if (!pw)
    throw new Error("vncWorld: no VNC password file (~/.samaltak-vnc or UEFI_VNC_PASSWORD): create one (at most 8 characters, mode 600)");
  if (await listening())
    throw new Error("vncWorld: 127.0.0.1:" + port + " is still in use after closing session " + session + ": another VM has display " + display);
  let built: { ok: boolean; seconds: number; errors: string[] } | undefined;
  if (input.build ?? true) {
    const b = await build({ target: "all", timeoutS: 280 });
    built = { ok: b.ok, seconds: b.seconds, errors: b.errors };
    if (!b.ok)
      return { target, action, session, keptLog: kept, build: built, ok: false, reason: "build failed: the World was not reopened" };
  }
  const s = await ctlSession({
    session,
    open: ["--uefi", "--window-size", windowSize, "--vnc", String(display), "--vnc-server", server, "--vnc-password-file", pwFile],
    env: { UEFI_GPU: gpu, UEFI_AFFINITY: affinity },
    keepOpen: true,
    continueOnError: true,
    openTimeoutS: 280,
    stepTimeoutS: 200,
    steps,
  });
  let up = false;
  for (let i = 0; i < 15 && !(up = await listening()); i++) await exec("sleep 2");
  // tools/qemu-pin.sh's line: the host CPUs QEMU runs on.
  const pinned =
    (await exec("grep -a -o 'qemu-pin: .*' \"${TMPDIR:-/tmp}/samaltak-ctl/" + session + ".log\" 2>/dev/null | tail -2")).stdout.trim() || undefined;
  return {
    target,
    action,
    ok: s.ok && up,
    session,
    server,
    port,
    listening: up,
    keptLog: kept,
    build: built,
    steps: stepLines(s.results),
    viewer: await openViewer(up),
    pinned,
    hint: up
      ? undefined
      : "127.0.0.1:" + port + " gives no RFB greeting: samaltak.crashLog({ session }) shows why the VM stopped" + (server === "image" ? " (or the image's display server did not start)" : ""),
  };
}
