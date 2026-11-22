/** The UEFI World on a VNC server for the operator's screen sharing (a samaltak-ctl --uefi session with UEFI_VNC): status (VM alive, VNC port, why it died), restart (keep the old log, close, build, open at 1920x1080 on virtio-gpu, send the agent and GitHub configs, optionally open Screen Sharing on the viewer's Mac), or close; dryRun shows the plan. */
async function vncWorld(
  { shell: { exec }, samaltak: { build, ctlSession, crashLog } },
  input: {
    action?: "status" | "restart" | "close";
    session?: string;
    display?: number;
    gpu?: string;
    windowSize?: string;
    configs?: Array<"agent" | "github">;
    build?: boolean;
    viewerHost?: string;
    dryRun?: boolean;
  } = {},
) {
  // The World the operator watches over VNC: tools/samaltak-ctl --session <session> open --uefi --window-size WxH with
  // UEFI_VNC=<display> (QEMU's VNC server on 127.0.0.1:5900+display, password file ~/.samaltak-vnc, UEFI_VNC_PASSWORD)
  // and UEFI_GPU=<gpu> (virtio-gpu-pci: 1920x1080; ramfb stops at 1024x768); docs/uefi.md. It runs from the current
  // directory's build (the operator's is the main checkout, session "vnc", display 1). Defaults: session "vnc", display 1,
  // gpu virtio-gpu-pci, windowSize 1920x1080, configs ["agent", "github"], build true.
  // status (default): alive (the session's VM), listening (the VNC port), and for a dead VM the crash triage of its log
  // (samaltak.crashLog: fatal line, exit status, collapsed stack). restart: copies the session's log aside
  // ($TMPDIR/samaltak-ctl/<session>-<time>.log; opening overwrites it), closes the session, builds (samaltak.build all),
  // opens it again (keepOpen), sends agent-config --from-pi (pi's API key, maybe through 1Password: the operator may have
  // to approve) and github-config --from-gh, checks the port, and with viewerHost (an ssh host, e.g. the operator's Mac;
  // it needs a LocalForward of the port to this machine) runs open "vnc://:<its ~/.samaltak-vnc>@localhost:<port>" there:
  // the password is read on that host and never printed. close: closes the session (its log kept aside first).
  // The operator's live VM: restart it only when asked; test on another session and display (e.g. "vnc-test", 7).
  const action = input.action ?? "status";
  const session = input.session ?? "vnc";
  if (!/^[A-Za-z0-9_-]+$/.test(session)) throw new Error("vncWorld: bad session name");
  const display = input.display ?? 1;
  if (!Number.isInteger(display) || display < 0 || display > 99)
    throw new Error("vncWorld: display is 0-99");
  const port = 5900 + display;
  const gpu = input.gpu ?? "virtio-gpu-pci";
  const windowSize = input.windowSize ?? "1920x1080";
  if (!/^[A-Za-z0-9_-]+$/.test(gpu) || !/^\d+x\d+$/.test(windowSize))
    throw new Error("vncWorld: bad gpu or windowSize");
  const configs = input.configs ?? ["agent", "github"];
  if (input.viewerHost && !/^[A-Za-z0-9_.@-]+$/.test(input.viewerHost))
    throw new Error("vncWorld: bad viewerHost");
  const listening = async () =>
    (await exec(`ss -ltn 2>/dev/null | grep -q '127.0.0.1:${port} '`)).code === 0;
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
              around: log.around && {
                before: log.around.before.slice(-6),
                after: log.around.after.slice(0, 12),
              },
              tail: log.tail,
            }
          : undefined,
      log: log?.file,
    };
  };
  const keepLog = async () =>
    (
      await exec(
        `L="\${TMPDIR:-/tmp}/samaltak-ctl/${session}.log"; [ -s "$L" ] || exit 0; K="\${TMPDIR:-/tmp}/samaltak-ctl/${session}-$(date +%Y%m%d-%H%M%S).log"; cp "$L" "$K" && echo "$K"`,
      )
    ).stdout.trim() || undefined;
  const close = async () => {
    const c = await exec(`tools/samaltak-ctl --session ${session} close </dev/null 2>&1`, {
      timeoutMs: 60000,
    });
    return c.stdout.trim().slice(-300);
  };
  if (action === "status") return { action, session, port, ...(await state()) };
  const steps: string[][] = [];
  if (configs.includes("agent")) steps.push(["agent-config", "--from-pi"]);
  if (configs.includes("github")) steps.push(["github-config", "--from-gh"]);
  const pw = (await exec('test -s "${UEFI_VNC_PASSWORD:-$HOME/.samaltak-vnc}"')).code === 0;
  if (input.dryRun)
    return {
      action,
      dryRun: true,
      session,
      port,
      now: await state(),
      plan: [
        "copy the session's log aside",
        `tools/samaltak-ctl --session ${session} close`,
        ...(action === "restart"
          ? [
              ...((input.build ?? true) ? ['samaltak.build({ target: "all" })'] : []),
              `UEFI_VNC=${display} UEFI_GPU=${gpu} tools/samaltak-ctl --session ${session} open --uefi --window-size ${windowSize}`,
              ...steps.map((s) => s.join(" ")),
              `check 127.0.0.1:${port} listens`,
              ...(input.viewerHost
                ? [`ssh ${input.viewerHost} open vnc://:<password>@localhost:${port}`]
                : []),
            ]
          : []),
      ],
      passwordFile: pw
        ? "present"
        : "missing: create ~/.samaltak-vnc (at most 8 characters, mode 600) first",
    };
  const kept = await keepLog();
  const closed = await close();
  if (action === "close")
    return { action, session, keptLog: kept, closed, listening: await listening() };
  if (!pw)
    throw new Error(
      "vncWorld: no VNC password file (~/.samaltak-vnc or UEFI_VNC_PASSWORD): create one (at most 8 characters, mode 600)",
    );
  if (await listening())
    throw new Error(
      `vncWorld: 127.0.0.1:${port} is still in use after closing session ${session}: another VM has display ${display}`,
    );
  let built: { ok: boolean; seconds: number; errors: string[] } | undefined;
  if (input.build ?? true) {
    const b = await build({ target: "all", timeoutS: 280 });
    built = { ok: b.ok, seconds: b.seconds, errors: b.errors };
    if (!b.ok)
      return {
        action,
        session,
        keptLog: kept,
        build: built,
        ok: false,
        reason: "build failed: the World was not reopened",
      };
  }
  const s = await ctlSession({
    session,
    open: ["--uefi", "--window-size", windowSize],
    env: { UEFI_VNC: String(display), UEFI_GPU: gpu },
    keepOpen: true,
    continueOnError: true,
    openTimeoutS: 280,
    stepTimeoutS: 200,
    steps,
  });
  let up = false;
  for (let i = 0; i < 15 && !(up = await listening()); i++) await exec("sleep 2");
  let viewer: string | undefined;
  if (input.viewerHost && up) {
    const v = await exec(
      `ssh -o BatchMode=yes -o ConnectTimeout=10 ${input.viewerHost} 'p=$(cat ~/.samaltak-vnc 2>/dev/null) || { echo "no ~/.samaltak-vnc there"; exit 1; }; open "vnc://:$p@localhost:${port}" && echo "Screen Sharing opened"' 2>&1`,
      { timeoutMs: 30000 },
    );
    viewer = v.stdout.trim().split("\n").pop();
  }
  return {
    action,
    ok: s.ok && up,
    session,
    port,
    listening: up,
    keptLog: kept,
    build: built,
    steps: s.results.map(
      (r) =>
        `${r.step.join(" ")}: ${r.code === 0 ? "ok" : `exit ${r.code}`} ${r.code === 0 ? r.out.slice(0, 80) : r.out.slice(-200)}${r.hint ? ` (${r.hint})` : ""}`,
    ),
    viewer,
    hint: up
      ? undefined
      : "the VNC port does not listen: samaltak.crashLog({ session }) shows why the VM stopped",
  };
}
