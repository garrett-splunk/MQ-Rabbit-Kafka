(function () {
  const STORAGE_KEY = "splunk-workshop-theme";
  const toast = document.getElementById("toast");
  const navLinks = document.querySelectorAll(".sidebar-tree__link[data-step]");
  const progressBar = document.getElementById("progressBar");
  const themeToggle = document.getElementById("themeToggle");
  const html = document.documentElement;

  function getSystemTheme() {
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }

  function applyTheme(mode) {
    const resolved = mode === "auto" ? getSystemTheme() : mode;
    html.setAttribute("data-theme", resolved);
    html.setAttribute("data-theme-mode", mode);
  }

  function cycleTheme() {
    const order = ["auto", "light", "dark"];
    const current = localStorage.getItem(STORAGE_KEY) || "auto";
    const next = order[(order.indexOf(current) + 1) % order.length];
    localStorage.setItem(STORAGE_KEY, next);
    applyTheme(next);
  }

  applyTheme(localStorage.getItem(STORAGE_KEY) || "auto");
  if (themeToggle) themeToggle.addEventListener("click", cycleTheme);

  document.querySelectorAll(".btn-copy").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const id = btn.getAttribute("data-copy");
      const el = document.getElementById(id);
      if (!el) return;
      try {
        await navigator.clipboard.writeText(el.textContent.trim());
        if (toast) {
          toast.textContent = "Copied to clipboard";
          toast.classList.add("show");
          setTimeout(() => toast.classList.remove("show"), 2000);
        }
      } catch {
        /* ignore */
      }
    });
  });

  const sections = [...navLinks]
    .map((link) => {
      const id = link.getAttribute("href")?.slice(1);
      const section = id ? document.getElementById(id) : null;
      return section ? { link, section } : null;
    })
    .filter(Boolean);

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          const match = sections.find((s) => s.section === entry.target);
          if (match) {
            navLinks.forEach((l) => {
              const on = l === match.link;
              l.classList.toggle("is-active", on);
            });
          }
        }
      });
    },
    { rootMargin: "-22% 0px -58% 0px", threshold: 0 }
  );
  sections.forEach(({ section }) => observer.observe(section));

  function updateProgress() {
    if (!progressBar) return;
    const doc = document.documentElement;
    const height = doc.scrollHeight - doc.clientHeight;
    progressBar.style.width = height > 0 ? `${((doc.scrollTop || document.body.scrollTop) / height) * 100}%` : "0%";
  }
  window.addEventListener("scroll", updateProgress, { passive: true });
  updateProgress();
})();
