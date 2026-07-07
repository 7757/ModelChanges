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
    return "en";
  }

  function applyLanguage(lang) {
    const pack = dict[lang] || dict.en;
    document.documentElement.lang = lang;
    document.querySelectorAll("[data-i18n]").forEach((node) => {
      const key = node.getAttribute("data-i18n");
      if (pack[key]) node.textContent = pack[key];
    });
    const shot = document.querySelector("[data-localized-shot]");
    if (shot) {
      shot.src = `assets/localized/endpoint-panel-${lang}.png`;
    }
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

  function wireReveal() {
    const targets = Array.from(document.querySelectorAll(
      ".hero-copy, .hero-visual, .section-heading, .feature-card, .step, .install-box, .download-links, .release-list li, .demo-frame"
    ));
    if (!targets.length) return;

    const reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce || !("IntersectionObserver" in window)) {
      targets.forEach((node) => node.classList.add("in-view"));
      return;
    }

    // Stagger items that share a parent (cards, steps, release items).
    const seen = new Map();
    targets.forEach((node) => {
      node.setAttribute("data-reveal", "");
      const index = seen.get(node.parentElement) || 0;
      seen.set(node.parentElement, index + 1);
      if (index > 0) node.style.setProperty("--reveal-delay", `${Math.min(index, 5) * 70}ms`);
    });

    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("in-view");
          observer.unobserve(entry.target);
        }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.12 });

    targets.forEach((node) => observer.observe(node));
  }

  wireLanguage();
  wireHeader();
  wireInstallCopy();
  wireReveal();
  loadDownloadCount();
  loadGoatCounter();
})();
