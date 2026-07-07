(function () {
  const config = window.ModelChangesSite || {};
  const dict = window.ModelChangesI18n || {};
  const supported = Object.keys(dict);
  const installCommand = `curl -fsSL https://${config.owner}.github.io/${config.repo}/install.sh | sh`;

  function preferredLanguage() {
    const requested = new URLSearchParams(window.location.search).get("lang");
    if (supported.includes(requested)) return requested;
    const saved = localStorage.getItem("modelchanges-language");
    if (supported.includes(saved)) return saved;
    const browser = navigator.language || "en";
    if (supported.includes(browser)) return browser;
    if (browser.startsWith("zh")) return "zh-CN";
    if (browser.startsWith("ja")) return "ja";
    if (browser.startsWith("ko")) return "ko";
    return "en";
  }

  function applyLanguage(lang) {
    const pack = dict[lang] || dict.en;
    document.documentElement.lang = lang;
    document.querySelectorAll("[data-i18n]").forEach((node) => {
      const key = node.getAttribute("data-i18n");
      if (pack[key]) node.textContent = pack[key];
    });
    const selector = document.querySelector("[data-language]");
    if (selector) selector.value = lang;
    localStorage.setItem("modelchanges-language", lang);
  }

  function wireLanguage() {
    const selector = document.querySelector("[data-language]");
    if (!selector) return;
    selector.addEventListener("change", () => applyLanguage(selector.value));
    applyLanguage(preferredLanguage());
  }

  function wireHeader() {
    const header = document.querySelector("[data-header]");
    if (!header) return;
    const update = () => header.classList.toggle("is-scrolled", window.scrollY > 16);
    update();
    window.addEventListener("scroll", update, { passive: true });
  }

  function wireInstallCopy() {
    const command = document.querySelector("[data-install-command]");
    const button = document.querySelector("[data-copy-install]");
    if (command) command.textContent = installCommand;
    if (!button) return;
    button.addEventListener("click", async () => {
      const original = button.textContent;
      await navigator.clipboard.writeText(installCommand);
      button.textContent = "Copied";
      window.setTimeout(() => {
        button.textContent = original;
      }, 1300);
    });
  }

  async function loadDownloadCount() {
    const holder = document.querySelector("[data-download-stat]");
    const count = document.querySelector("[data-download-count]");
    if (!holder || !count || !config.owner || !config.repo) return;
    try {
      const response = await fetch(`https://api.github.com/repos/${config.owner}/${config.repo}/releases`, {
        headers: { "Accept": "application/vnd.github+json" }
      });
      if (!response.ok) return;
      const releases = await response.json();
      const total = releases.flatMap((release) => release.assets || [])
        .reduce((sum, asset) => sum + (asset.download_count || 0), 0);
      if (total <= 0) return;
      count.textContent = total.toLocaleString();
      holder.hidden = false;
    } catch (_) {
      holder.hidden = true;
    }
  }

  function loadGoatCounter() {
    const code = config.goatCounterCode;
    if (!code) return;
    const script = document.createElement("script");
    script.async = true;
    script.src = "//gc.zgo.at/count.js";
    script.dataset.goatcounter = `https://${code}.goatcounter.com/count`;
    document.body.appendChild(script);
  }

  wireLanguage();
  wireHeader();
  wireInstallCopy();
  loadDownloadCount();
  loadGoatCounter();
})();
