// VIO — mobile menu toggle
(function () {
  var nav = document.querySelector(".nav");
  var toggle = document.querySelector(".nav__toggle");
  if (!nav || !toggle) return;

  function setOpen(open) {
    nav.classList.toggle("is-open", open);
    toggle.setAttribute("aria-expanded", String(open));
    toggle.setAttribute("aria-label", open ? "Close menu" : "Open menu");
  }

  toggle.addEventListener("click", function () {
    setOpen(!nav.classList.contains("is-open"));
  });

  // close when a menu link is tapped
  nav.querySelectorAll(".nav__menu a").forEach(function (link) {
    link.addEventListener("click", function () {
      setOpen(false);
    });
  });

  // close on Escape
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") setOpen(false);
  });

  // reset when resizing up to desktop
  window.matchMedia("(min-width: 900px)").addEventListener("change", function (e) {
    if (e.matches) setOpen(false);
  });
})();