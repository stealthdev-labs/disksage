// Tiny, dependency-free progressive enhancement: scroll-reveal + nav state.
(function () {
  "use strict";

  // --- Nav: solid background once the page is scrolled ---
  const nav = document.getElementById("nav");
  const onScroll = () => nav && nav.classList.toggle("scrolled", window.scrollY > 8);
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  // --- Copy-to-clipboard for the donation wallet ---
  document.querySelectorAll(".copy-wallet").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const addr = btn.getAttribute("data-wallet") || "";
      try {
        await navigator.clipboard.writeText(addr);
      } catch (e) {
        const r = document.createRange();
        const code = btn.parentElement.parentElement.querySelector(".wallet");
        if (code) { r.selectNode(code); getSelection().removeAllRanges(); getSelection().addRange(r); }
      }
      const label = btn.textContent;
      btn.textContent = "Copied ✓";
      btn.classList.add("copied");
      setTimeout(() => { btn.textContent = label; btn.classList.remove("copied"); }, 1600);
    });
  });

  // --- Scroll reveal ---
  const reveal = document.querySelectorAll("[data-reveal]");
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  if (reduce || !("IntersectionObserver" in window)) {
    reveal.forEach((el) => el.classList.add("in"));
    return;
  }

  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("in");
          io.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
  );
  reveal.forEach((el) => io.observe(el));
})();
