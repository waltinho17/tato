(function () {
  "use strict";

  // Lets the stylesheet hide reveal-on-scroll elements only when JavaScript is available.
  document.documentElement.classList.add("js");

  // ------------------------------------------------------------------ configuration
  var REPO = "waltinho17/tato";
  // Feedback delivery, in order of preference:
  //  1. FEEDBACK_ENDPOINT: a Formspree form URL (https://formspree.io/f/XXXX). Messages reach the owner's inbox
  //     privately and the owner's email address never appears on this page.
  //  2. FEEDBACK_EMAIL: opens the visitor's email app. The address becomes public in this file.
  //  3. Neither set: opens a public GitHub issue.
  var FEEDBACK_ENDPOINT = "";
  var FEEDBACK_EMAIL = "";

  var reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  document.addEventListener("DOMContentLoaded", function () {
    var body = document.body;
    var lang = body.getAttribute("data-lang") || "en";

    wrapHeadlineWords();
    rotator();
    reveal();
    download(lang);
    prefTabs();
    feedback(lang);

    // ---------------------------------------------------------------- headline: reveal word by word
    function wrapHeadlineWords() {
      var anim = document.querySelector(".headline .anim");
      if (!anim) return;
      var index = 1;                                   // the rotating word is index 0
      var nodes = Array.prototype.slice.call(anim.childNodes);
      nodes.forEach(function (node) {
        if (node.nodeType === 3) {                      // plain text: one span per word
          var frag = document.createDocumentFragment();
          node.textContent.split(/(\s+)/).forEach(function (part) {
            if (!part) return;
            if (/^\s+$/.test(part)) { frag.appendChild(document.createTextNode(" ")); return; }
            frag.appendChild(word(part, index++));
          });
          anim.replaceChild(frag, node);
        } else if (node.nodeType === 1 && !node.hasAttribute("data-rot")) {   // e.g. <span class="tb">Touch Bar</span>
          var text = node.textContent;
          node.textContent = "";
          text.split(/(\s+)/).forEach(function (part) {
            if (!part) return;
            node.appendChild(/^\s+$/.test(part) ? document.createTextNode(" ") : word(part, index++));
          });
        }
      });
      function word(text, i) {
        var s = document.createElement("span");
        s.className = "hw";
        s.style.setProperty("--i", i);
        s.textContent = text;
        return s;
      }
    }

    // ---------------------------------------------------------------- headline: rotating word
    function rotator() {
      var rot = document.querySelector("[data-rot]");
      if (!rot || reduceMotion) return;
      var words = rot.querySelectorAll("span");
      if (words.length < 2) return;
      var current = 0;
      function fit() { rot.style.width = words[current].offsetWidth + "px"; }
      fit();
      if (document.fonts && document.fonts.ready) document.fonts.ready.then(fit);
      window.addEventListener("resize", fit);
      setInterval(function () {
        var prev = words[current];
        current = (current + 1) % words.length;
        prev.classList.remove("on");
        prev.classList.add("out");
        words[current].classList.add("on");
        fit();
        setTimeout(function () { prev.classList.remove("out"); }, 750);   // ready to re-enter from below
      }, 2600);
    }

    // ---------------------------------------------------------------- scroll reveal
    function reveal() {
      var items = document.querySelectorAll(".rv");
      if (!("IntersectionObserver" in window) || reduceMotion) {
        items.forEach(function (el) { el.classList.add("in"); });
        return;
      }
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
        });
      }, { threshold: 0.12, rootMargin: "0px 0px -6% 0px" });
      items.forEach(function (el) { io.observe(el); });
    }

    // ---------------------------------------------------------------- download: point the button at the latest .zip
    function download(lang) {
      var btn = document.getElementById("download");
      var label = document.getElementById("download-label");
      var meta = document.getElementById("download-meta");
      if (!btn) return;
      fetch("https://api.github.com/repos/" + REPO + "/releases/latest", { headers: { Accept: "application/vnd.github+json" } })
        .then(function (r) { return r.ok ? r.json() : Promise.reject(); })
        .then(function (rel) {
          var assets = rel.assets || [];
          var zip = assets.filter(function (a) { return /\.zip$/i.test(a.name); })[0] || assets[0];
          var prefix = "https://github.com/" + REPO + "/";
          if (zip && typeof zip.browser_download_url === "string" && zip.browser_download_url.indexOf(prefix) === 0) {
            btn.href = zip.browser_download_url;
            label.textContent = body.getAttribute("data-dl-prefix") + " " + String(rel.tag_name || "").replace(/^v/, "");
            var mb = zip.size ? " · " + (zip.size / 1048576).toLocaleString(lang === "pt" ? "pt-BR" : "en-US", { maximumFractionDigits: 1 }) + " MB" : "";
            meta.textContent = body.getAttribute("data-dl-meta") + mb;
          }
        })
        .catch(function () { /* keeps the link to the releases page */ });
    }

    // ---------------------------------------------------------------- preferences screenshots
    function prefTabs() {
      var img = document.getElementById("prefs-img");
      var tabs = document.querySelectorAll(".tabs button");
      if (!img) return;
      tabs.forEach(function (t) {
        t.addEventListener("click", function () {
          tabs.forEach(function (o) { o.setAttribute("aria-selected", o === t ? "true" : "false"); });
          img.classList.add("swap");
          setTimeout(function () {
            img.src = t.getAttribute("data-img");
            img.alt = t.getAttribute("data-alt");
            img.classList.remove("swap");
          }, 180);
        });
      });
    }

    // ---------------------------------------------------------------- feedback form
    function feedback(lang) {
      var form = document.getElementById("feedback");
      if (!form) return;
      var note = document.getElementById("fb-note");
      var emailWrap = document.getElementById("fb-email-wrap");
      var button = form.querySelector("button[type=submit]");
      var endpoint = /^https:\/\/formspree\.io\/f\/[A-Za-z0-9]+$/.test(FEEDBACK_ENDPOINT) ? FEEDBACK_ENDPOINT : "";
      var sent = 0;

      function say(text, cls) { note.textContent = text; note.className = "form-note" + (cls ? " " + cls : ""); }

      if (endpoint) { emailWrap.hidden = false; say(body.getAttribute("data-ok-form")); }
      else if (FEEDBACK_EMAIL) { emailWrap.hidden = false; say(body.getAttribute("data-ok-mail")); }
      else { say(body.getAttribute("data-ok-issue"), "warn"); }

      form.addEventListener("submit", function (e) {
        e.preventDefault();
        var type = document.getElementById("fb-type").value;
        var msg = document.getElementById("fb-msg").value.trim();
        var from = document.getElementById("fb-email").value.trim();
        if (!msg) { say(body.getAttribute("data-err-empty"), "warn"); return; }
        if (document.getElementById("fb-trap").value) { say(body.getAttribute("data-sent"), "good"); return; }   // bots fill the hidden field
        if (sent >= 3) return;                                                                                       // light client-side throttle
        var title = "[" + type + "] " + msg.split("\n")[0].slice(0, 70);

        if (endpoint) {
          sent++; button.disabled = true; say(body.getAttribute("data-sending"));
          fetch(endpoint, {
            method: "POST",
            headers: { "Content-Type": "application/json", Accept: "application/json" },
            body: JSON.stringify({ type: type, message: msg, email: from, language: lang, subject: "Tato: " + title })
          }).then(function (r) {
            if (!r.ok) throw new Error();
            form.reset(); say(body.getAttribute("data-sent"), "good");
          }).catch(function () {
            say(body.getAttribute("data-fail"), "warn");
          }).then(function () { setTimeout(function () { button.disabled = false; }, 8000); });
        } else if (FEEDBACK_EMAIL) {
          var text = msg + (from ? "\n\nReply to: " + from : "");
          window.location.href = "mailto:" + encodeURIComponent(FEEDBACK_EMAIL) + "?subject=" + encodeURIComponent("Tato: " + title) + "&body=" + encodeURIComponent(text);
        } else {
          window.open("https://github.com/" + REPO + "/issues/new?title=" + encodeURIComponent(title) + "&body=" + encodeURIComponent(msg), "_blank", "noopener");
        }
      });
    }
  });
})();
