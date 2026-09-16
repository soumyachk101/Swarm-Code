(function () {
  "use strict";

  var root = document.getElementById("changelog-root");
  if (!root) return;

  var VISIBLE_ITEMS_PER_GROUP = 5;

  var GROUP_LABELS = {
    "new features": "New features",
    "bug fixes": "Bug fixes",
    "refinements": "Refinements",
    "updates": "Updates"
  };

  function setState(kind, buildInner) {
    root.replaceChildren();
    root.setAttribute("aria-busy", kind === "loading" ? "true" : "false");
    var stateEl = document.createElement("div");
    stateEl.className = "changelog-state";
    stateEl.setAttribute("data-changelog-state", kind);
    buildInner(stateEl);
    root.appendChild(stateEl);
  }

  function showLoading() {
    setState("loading", function (el) {
      var spinner = document.createElement("div");
      spinner.className = "changelog-spinner";
      spinner.setAttribute("aria-hidden", "true");
      var text = document.createElement("p");
      text.className = "changelog-state__text";
      text.textContent = "Loading release notes...";
      el.appendChild(spinner);
      el.appendChild(text);
    });
  }

  function showError() {
    setState("error", function (el) {
      var title = document.createElement("p");
      title.className = "changelog-state__title";
      title.textContent = "Couldn't load the changelog";
      var text = document.createElement("p");
      text.className = "changelog-state__text";
      text.textContent = "Check your connection and try again.";
      var retry = document.createElement("button");
      retry.type = "button";
      retry.className = "btn btn--sm";
      retry.textContent = "Try again";
      retry.addEventListener("click", loadChangelog);
      el.appendChild(title);
      el.appendChild(text);
      el.appendChild(retry);
    });
  }

  function showEmpty() {
    setState("empty", function (el) {
      var title = document.createElement("p");
      title.className = "changelog-state__title";
      title.textContent = "No releases yet";
      var text = document.createElement("p");
      text.className = "changelog-state__text";
      text.textContent = "Check back soon, new releases will show up here first.";
      el.appendChild(title);
      el.appendChild(text);
    });
  }

  function formatDate(raw) {
    if (typeof raw !== "string") return "";
    var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw.trim());
    if (!match) return raw;
    var date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
    if (isNaN(date.getTime())) return raw;
    try {
      return date.toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" });
    } catch (err) {
      return raw;
    }
  }

  function groupLabel(title) {
    var key = String(title || "").trim().toLowerCase();
    return GROUP_LABELS[key] || (String(title || "").trim() || "Updates");
  }

  function buildGroup(section) {
    if (!section || typeof section !== "object") return null;
    var items = (Array.isArray(section.items) ? section.items : []).filter(function (item) {
      return item !== null && item !== undefined && item !== "";
    });
    if (!items.length) return null;

    var block = document.createElement("div");
    block.className = "changelog-group";
    var heading = document.createElement("h3");
    heading.className = "changelog-group__label";
    heading.textContent = groupLabel(section.title);
    block.appendChild(heading);

    var list = document.createElement("ul");
    list.className = "changelog-item-list";

    function appendItem(item) {
      var li = document.createElement("li");
      li.className = "changelog-item";
      li.textContent = String(item);
      list.appendChild(li);
    }

    items.slice(0, VISIBLE_ITEMS_PER_GROUP).forEach(appendItem);
    block.appendChild(list);

    var hidden = items.slice(VISIBLE_ITEMS_PER_GROUP);
    if (hidden.length) {
      var more = document.createElement("button");
      more.type = "button";
      more.className = "changelog-more";
      more.textContent = "Show " + hidden.length + " more";
      more.addEventListener("click", function () {
        hidden.forEach(appendItem);
        more.remove();
      });
      block.appendChild(more);
    }
    return block;
  }

  function buildEntry(release, index) {
    var entry = document.createElement("article");
    entry.className = "changelog-entry reveal";
    entry.style.setProperty("--reveal-delay", Math.min(index * 70, 350) + "ms");

    var version = typeof release.version === "string" && release.version.trim()
      ? release.version.trim() : "";

    var dateEl = document.createElement("p");
    dateEl.className = "changelog-entry__date";
    dateEl.textContent = formatDate(release.date);
    entry.appendChild(dateEl);

    var title = document.createElement("h2");
    title.className = "changelog-entry__title";
    title.textContent = version ? "Droppy Code " + version : "New release";
    entry.appendChild(title);

    if (version) {
      var versionLine = document.createElement("p");
      versionLine.className = "changelog-entry__version";
      versionLine.textContent = version;
      entry.appendChild(versionLine);
    }

    var summary = typeof release.summary === "string" ? release.summary.trim() : "";
    if (summary) {
      var summaryEl = document.createElement("p");
      summaryEl.className = "changelog-entry__summary";
      summaryEl.textContent = summary;
      entry.appendChild(summaryEl);
    }

    var sections = Array.isArray(release.sections) ? release.sections : [];
    var groups = [];
    sections.forEach(function (section) {
      var block = buildGroup(section);
      if (block) groups.push(block);
    });
    if (groups.length) {
      var whatsnew = document.createElement("p");
      whatsnew.className = "changelog-whatsnew";
      whatsnew.textContent = "What's new:";
      entry.appendChild(whatsnew);
      groups.forEach(function (block) { entry.appendChild(block); });
    }
    return entry;
  }

  function renderReleases(data) {
    var releases = data && Array.isArray(data.releases) ? data.releases : [];
    if (!releases.length) { showEmpty(); return; }
    var fragment = document.createDocumentFragment();
    var cards = [];
    releases.forEach(function (release, index) {
      if (!release || typeof release !== "object") return;
      var card = buildEntry(release, index);
      cards.push(card);
      fragment.appendChild(card);
    });
    if (!cards.length) { showEmpty(); return; }
    root.replaceChildren();
    root.setAttribute("aria-busy", "false");
    root.appendChild(fragment);
    if ("IntersectionObserver" in window) {
      var observer = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
          }
        });
      }, { root: null, rootMargin: "0px 0px -5% 0px", threshold: 0 });
      cards.forEach(function (el) { observer.observe(el); });
    } else {
      cards.forEach(function (el) { el.classList.add("is-visible"); });
    }
  }

  function loadChangelog() {
    showLoading();
    fetch("changelog.json", { cache: "no-cache" })
      .then(function (response) {
        if (!response.ok) throw new Error("Changelog request failed with status " + response.status);
        return response.json();
      })
      .then(renderReleases)
      .catch(function (err) {
        console.error("[changelog] failed to load changelog.json:", err);
        showError();
      });
  }

  loadChangelog();
})();
