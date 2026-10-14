/* Covenant: AD search only from «Пригласить». Regular executor search stays Pulse users. */
(function () {
  if (window.__covenantAdInvite === "20260910e") return;
  window.__covenantAdInvite = "20260910e";

  function csrf() {
    var m = document.querySelector('meta[name="csrf-token"]');
    return m ? m.getAttribute("content") : "";
  }

  function projectId() {
    var m = location.pathname.match(/\/projects\/([^/?#]+)/);
    if (m) return decodeURIComponent(m[1]);
    var el =
      document.querySelector("[data-project-identifier]") ||
      document.querySelector("meta[name='current_project']") ||
      document.querySelector("[data-project-id]");
    if (el) {
      return (
        el.getAttribute("data-project-identifier") ||
        el.getAttribute("content") ||
        el.getAttribute("data-project-id") ||
        ""
      );
    }
    if (window.gon && gon.project_identifier) return gon.project_identifier;
    return "";
  }

  function markCreatePage() {
    var create = /\/work_packages\/(?:details\/)?new(?:\/|$|\?)/.test(location.pathname + location.search);
    document.documentElement.classList.toggle("covenant-wp-create", create);
  }

  function qs(sel, root) {
    return (root || document).querySelector(sel);
  }

  var dialog = null;
  var timer = null;
  var lastFieldHost = null;
  var retryTimers = [];

  function injectStyles() {
    if (document.getElementById("covenant-ad-invite-css")) return;
    var style = document.createElement("style");
    style.id = "covenant-ad-invite-css";
    style.textContent = [
      "dialog.covenant-ad-invite{all:revert;position:fixed;inset:0;width:min(460px,calc(100vw - 32px));max-height:min(80vh,640px);margin:auto;padding:0;border:0;border-radius:12px;background:#fff;color:#1a1a1a;box-shadow:0 24px 48px rgba(15,23,42,.28);font-family:var(--body-font-family,Inter,Segoe UI,sans-serif);z-index:20000;}",
      "dialog.covenant-ad-invite[open]{display:flex;flex-direction:column;}",
      "dialog.covenant-ad-invite::backdrop{background:rgba(15,23,42,.5);}",
      ".covenant-ad-invite__head{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:16px 20px;border-bottom:1px solid #e5e7eb;}",
      ".covenant-ad-invite__head h2{margin:0;font-size:18px;font-weight:600;line-height:1.3;}",
      ".covenant-ad-invite__x{border:0;background:transparent;color:#4b5563;font-size:22px;line-height:1;cursor:pointer;padding:0 4px;}",
      ".covenant-ad-invite__body{padding:16px 20px 8px;overflow:auto;}",
      ".covenant-ad-invite__label{display:block;margin:0 0 6px;font-size:13px;font-weight:600;color:#344054;}",
      ".covenant-ad-invite__q{display:block;width:100%;box-sizing:border-box;height:40px;padding:8px 12px;border:1px solid #d0d5dd;border-radius:8px;background:#fff;font-size:14px;line-height:24px;}",
      ".covenant-ad-invite__q:focus{outline:2px solid #4f8ff0;outline-offset:1px;border-color:#4f8ff0;}",
      ".covenant-ad-invite__hint,.covenant-ad-invite__status{margin:8px 0 0;font-size:13px;color:#667085;}",
      ".covenant-ad-invite__status.is-error{color:#b42318;}",
      ".covenant-ad-invite__list{list-style:none;margin:12px 0 0;padding:0;max-height:280px;overflow:auto;}",
      ".covenant-ad-invite__person{display:flex;flex-direction:column;align-items:flex-start;gap:2px;width:100%;margin:0 0 8px;padding:10px 12px;border:1px solid #e5e7eb;border-radius:8px;background:#f9fafb;cursor:pointer;text-align:left;font:inherit;}",
      ".covenant-ad-invite__person:hover{background:#eef4ff;border-color:#b6c8f5;}",
      ".covenant-ad-invite__person span{font-size:12px;color:#667085;}",
      ".covenant-ad-invite__foot{display:flex;justify-content:flex-end;padding:12px 20px 16px;}",
      ".covenant-ad-invite__cancel{height:36px;padding:0 14px;border:1px solid #d0d5dd;border-radius:8px;background:#fff;color:#344054;font-size:14px;cursor:pointer;}",
      "op-invite-user-button,.op-invite-user-button{display:none!important;}",
      ".covenant-ad-invite__field-btn{display:inline-flex;align-items:center;gap:6px;height:28px;padding:0 10px;margin:0 0 0 8px;border:1px solid var(--borderColor-muted,#d0d5dd);border-radius:6px;background:var(--overlay-bgColor,#fff);color:var(--fgColor-accent,#1d4ed8);font:600 12px/1 var(--body-font-family,Inter,Segoe UI,sans-serif);cursor:pointer;vertical-align:middle;white-space:nowrap;}",
      ".covenant-ad-invite__field-btn:hover{background:var(--control-bgColor-hover,#f3f4f6);}",
      ".covenant-ad-invite__field-btn svg{width:14px;height:14px;flex:0 0 14px;}",
      ".covenant-ad-invite__field-btn--under{margin:8px 0 0;}",
      ".covenant-ad-invite__field-btn--table{display:inline-flex;align-items:center;gap:5px;height:auto;margin:6px 0 0;padding:0;border:0;border-radius:0;background:transparent;box-shadow:none;color:#1d4ed8;font:600 12px/1.2 var(--body-font-family,Inter,Segoe UI,sans-serif);}",
      ".covenant-ad-invite__field-btn--table:hover{background:transparent;text-decoration:underline;}",
      ".wp-table--cell-container:has(.covenant-ad-invite__field-btn--table),.inline-edit--active-field:has(.covenant-ad-invite__field-btn--table),.wp-table--cell-td:has(.covenant-ad-invite__field-btn--table){overflow:visible!important;}",
      ".covenant-ad-invite__dd-btn{display:flex;align-items:center;gap:8px;width:100%;box-sizing:border-box;margin:0;padding:10px 12px;border:0;border-top:1px solid #e5e7eb;background:#fff;color:#1d4ed8;font:600 13px/1.3 var(--body-font-family,Inter,Segoe UI,sans-serif);text-align:left;cursor:pointer;}",
      ".covenant-ad-invite__dd-btn:hover{background:#f5f8ff;}",
      ".covenant-ad-invite__cell-btn{display:inline-flex;align-items:center;gap:5px;margin:6px 0 0;padding:0;border:0;background:transparent;color:#1d4ed8;font:600 12px/1.2 var(--body-font-family,Inter,Segoe UI,sans-serif);cursor:pointer;white-space:nowrap;}",
      ".covenant-ad-invite__cell-btn[hidden]{display:none!important;}",
      ".wp-table--cell-container:has(.covenant-ad-invite__cell-btn),.inline-edit--active-field:has(.covenant-ad-invite__cell-btn),.wp-inline-create-row td:has(.covenant-ad-invite__cell-btn){overflow:visible!important;}"
    ].join("");
    document.head.appendChild(style);
  }

  function ensureModal() {
    if (dialog) return dialog;
    injectStyles();
    dialog = document.createElement("dialog");
    dialog.className = "covenant-ad-invite";
    dialog.setAttribute("aria-labelledby", "covenant-ad-invite-title");
    dialog.innerHTML =
      '<div class="covenant-ad-invite__head">' +
      '<h2 id="covenant-ad-invite-title">Пригласить из AD</h2>' +
      '<button type="button" class="covenant-ad-invite__x" data-covenant-ad-close="1" aria-label="Закрыть">×</button>' +
      "</div>" +
      '<div class="covenant-ad-invite__body">' +
      '<label class="covenant-ad-invite__label" for="covenant-ad-invite-q">Фамилия, логин или почта</label>' +
      '<input id="covenant-ad-invite-q" type="text" class="covenant-ad-invite__q" placeholder="Начните вводить — ищем в каталоге завода" autocomplete="off" spellcheck="false">' +
      '<p class="covenant-ad-invite__hint">Только это предприятие. Кто уже заходил в Пульс — в обычном списке исполнителей.</p>' +
      '<div class="covenant-ad-invite__status" role="status"></div>' +
      '<ul class="covenant-ad-invite__list"></ul>' +
      "</div>" +
      '<div class="covenant-ad-invite__foot">' +
      '<button type="button" class="covenant-ad-invite__cancel" data-covenant-ad-close="1">Закрыть</button>' +
      "</div>";
    document.body.appendChild(dialog);
    dialog.addEventListener("click", function (e) {
      if (e.target.getAttribute("data-covenant-ad-close")) closeModal();
    });
    dialog.addEventListener("cancel", function (e) {
      e.preventDefault();
      closeModal();
    });
    qs(".covenant-ad-invite__q", dialog).addEventListener("input", function (e) {
      scheduleSearch(e.target.value);
    });
    return dialog;
  }

  function setStatus(text, isError) {
    var el = qs(".covenant-ad-invite__status", dialog);
    if (!el) return;
    el.textContent = text || "";
    el.classList.toggle("is-error", !!isError);
  }

  function closeModal() {
    if (!dialog) return;
    if (dialog.open) dialog.close();
    var list = qs(".covenant-ad-invite__list", dialog);
    var input = qs(".covenant-ad-invite__q", dialog);
    if (list) list.innerHTML = "";
    if (input) input.value = "";
    setStatus("");
  }

  function openModal() {
    if (!projectId()) {
      window.alert("Откройте ковенанту внутри предприятия.");
      return;
    }
    ensureModal();
    if (!dialog.open) dialog.showModal();
    setTimeout(function () {
      var input = qs(".covenant-ad-invite__q", dialog);
      if (input) input.focus();
    }, 0);
  }

  function scheduleSearch(q) {
    clearTimeout(timer);
    timer = setTimeout(function () {
      runSearch(q);
    }, 250);
  }

  function runSearch(q) {
    q = (q || "").trim();
    var list = qs(".covenant-ad-invite__list", dialog);
    list.innerHTML = "";
    if (q.length < 2) {
      setStatus("Введите минимум 2 символа.");
      return;
    }
    setStatus("Ищем в AD…");
    var url =
      "/covenant/ad_invite/search?project_id=" +
      encodeURIComponent(projectId()) +
      "&q=" +
      encodeURIComponent(q);
    fetch(url, { credentials: "same-origin", headers: { Accept: "application/json" } })
      .then(function (r) {
        return r.json();
      })
      .then(function (data) {
        if (data.error) {
          setStatus(data.error, true);
          return;
        }
        var people = data.people || [];
        if (!people.length) {
          setStatus("В этом предприятии никого не нашли.");
          return;
        }
        setStatus("Нашли " + people.length + ". Клик — добавим в исполнители, форма не сбросится.");
        people.forEach(function (p) {
          var li = document.createElement("li");
          var btn = document.createElement("button");
          btn.type = "button";
          btn.className = "covenant-ad-invite__person";
          btn.innerHTML = "<strong></strong><span></span>";
          btn.querySelector("strong").textContent = p.name || p.login;
          btn.querySelector("span").textContent =
            (p.login || "") + (p.mail ? " · " + p.mail : "");
          btn.addEventListener("click", function () {
            invite(p.login);
          });
          li.appendChild(btn);
          list.appendChild(li);
        });
      })
      .catch(function () {
        setStatus("Каталог недоступен.", true);
      });
  }

  function walkNgContext(el, fn) {
    var seen = typeof WeakSet === "function" ? new WeakSet() : null;
    function inspect(v, depth) {
      if (!v || depth > 7 || typeof v !== "object") return false;
      if (seen) {
        if (seen.has(v)) return false;
        seen.add(v);
      }
      if (fn(v)) return true;
      if (Array.isArray(v) && v.length < 120) {
        for (var i = 0; i < v.length; i++) {
          if (inspect(v[i], depth + 1)) return true;
        }
      }
      return false;
    }
    var node = el;
    while (node) {
      if (inspect(node.__ngContext__, 0)) return true;
      node = node.parentElement;
    }
    return false;
  }

  function workPackageId() {
    var el = lastFieldHost;
    if (el && el.closest) {
      var row = el.closest("[data-work-package-id]");
      if (row) {
        var rid = row.getAttribute("data-work-package-id") || "";
        if (/^\d+$/.test(rid)) return rid;
      }
    }
    var m = location.pathname.match(/\/work_packages\/(\d+)(?:\/|$)/);
    return m ? m[1] : "";
  }

  var pendingInvites = [];
  var knownWpIds = {};
  var pendingWatch = null;
  var createRowSeen = false;
  var createRowGoneAt = null;
  var knownWpIdsFrozen = false;

  function snapshotKnownWpIds() {
    if (knownWpIdsFrozen) return;
    document.querySelectorAll("[data-work-package-id]").forEach(function (el) {
      var id = el.getAttribute("data-work-package-id") || "";
      if (/^\d+$/.test(id)) knownWpIds[id] = true;
    });
  }

  function isUnsavedInlineRow() {
    if (document.querySelector(".wp-inline-create-row")) return true;
    if (lastFieldHost && lastFieldHost.closest) {
      if (lastFieldHost.closest(".wp-inline-create-row")) return true;
      var row = lastFieldHost.closest("[data-work-package-id]");
      if (row && !/^\d+$/.test(row.getAttribute("data-work-package-id") || "")) return true;
    }
    return false;
  }

  function isExecutorFieldName(name) {
    rememberCfFromDom();
    var keys = Object.keys(learnedCf);
    if (!keys.length) return /customField\d+/.test(String(name));
    return !!learnedCf[name];
  }

  function queuePendingExecutor(p) {
    if (!p || (!p.userId && !p.login)) return;
    var exists = pendingInvites.some(function (x) {
      return (p.userId && String(x.userId) === String(p.userId)) || (p.login && x.login === p.login);
    });
    if (!exists) pendingInvites.push({ userId: p.userId, login: p.login, name: p.name, at: Date.now() });
    if (!knownWpIdsFrozen) {
      snapshotKnownWpIds();
      knownWpIdsFrozen = true;
    }
    startPendingWatch();
  }

  function harvestInlineCreateExecutors() {
    var row = document.querySelector(".wp-inline-create-row");
    if (!row) return;
    walkNgContext(row, function (v) {
      if (!v || !v.resource || !v.name) return false;
      if (!isExecutorFieldName(v.name)) return false;
      var val = v.resource[v.name];
      if (!val) return false;
      [].concat(val).forEach(function (u) {
        if (!u) return;
        var href = (u.href || (u.$links && u.$links.self && u.$links.self.href) || "") + "";
        var id = u.id || (href && href.split("/").pop());
        if (id && /^\d+$/.test(String(id))) {
          queuePendingExecutor({ userId: id, login: u.login, name: u.name });
        }
      });
      return false;
    });
  }

  function noteInlineCreateLifecycle() {
    var creating = !!document.querySelector(".wp-inline-create-row");
    if (creating) {
      if (!createRowSeen) {
        snapshotKnownWpIds();
        knownWpIdsFrozen = true;
      }
      createRowSeen = true;
      createRowGoneAt = null;
      startPendingWatch();
      return;
    }
    if (createRowSeen && !createRowGoneAt) createRowGoneAt = Date.now();
  }

  function dropStalePending() {
    if (!createRowGoneAt || document.querySelector(".wp-inline-create-row")) return;
    if (Date.now() - createRowGoneAt < 3500) return;
    pendingInvites = [];
    createRowSeen = false;
    createRowGoneAt = null;
    knownWpIdsFrozen = false;
  }

  function clearPendingCreate() {
    pendingInvites = [];
    createRowSeen = false;
    createRowGoneAt = null;
    knownWpIdsFrozen = false;
  }

  function wpIdFromApiUrl(url) {
    var m = String(url || "").match(/\/api\/v3\/work_packages\/(\d+)(?:\/|$|\?)/);
    return m ? m[1] : "";
  }

  function bodyHasExecutorsCf(body) {
    var cf = executorsCfName();
    if (!cf || body == null) return false;
    var s = typeof body === "string" ? body : "";
    if (!s) {
      try {
        s = JSON.stringify(body);
      } catch (e) {
        return false;
      }
    }
    return s.indexOf(cf) !== -1;
  }

  function paintExecutorsCell(wpId, names) {
    names = (names || []).filter(Boolean);
    if (!names.length) return;
    var row = document.querySelector('[data-work-package-id="' + wpId + '"]');
    if (!row) return;
    var cf = executorsCfName();
    var display =
      (cf && row.querySelector("." + cf + " .inline-edit--display-field")) ||
      row.querySelector('[id*="customField"] .inline-edit--display-field');
    if (!display) return;
    display.textContent = names.join(", ");
    display.classList.remove("-empty");
    display.setAttribute("aria-label", "Исполнители " + names.join(", "));
  }

  function namesFromWp(wp, cf) {
    var names = [];
    if (!wp || !cf) return names;
    var val = wp[cf];
    [].concat(val || []).forEach(function (u) {
      if (u && u.name) names.push(u.name);
    });
    var links = wp.$source && wp.$source._links && wp.$source._links[cf];
    if (!names.length && links) {
      [].concat(links).forEach(function (l) {
        if (l && l.title) names.push(l.title);
      });
    }
    return names;
  }

  function refreshWorkPackage(wpId) {
    if (!wpId || !/^\d+$/.test(String(wpId))) return;
    if (!window.OpenProject || !OpenProject.getPluginContext) return;
    OpenProject.getPluginContext().then(function (plugin) {
      plugin.runInZone(function () {
        var svc = plugin.services || {};
        var api = svc.apiV3Service && svc.apiV3Service.work_packages.id(String(wpId));
        if (!api) return;
        var apply = function (wp) {
          if (!wp) return;
          try {
            if (svc.halEvents && svc.halEvents.push) svc.halEvents.push(wp, { event: "updated" });
          } catch (e) {}
          paintExecutorsCell(wpId, namesFromWp(wp, executorsCfName()));
        };
        var req = api.refresh ? api.refresh() : api.requireAndStream && api.requireAndStream(true);
        if (req && req.subscribe) req.subscribe(apply, function () {});
        else if (api.get) api.get().subscribe(apply, function () {});
      });
    });
  }

  function scheduleExecutorRefresh(wpId) {
    if (!wpId || !/^\d+$/.test(String(wpId))) return;
    var tries = 0;
    var run = function () {
      var row = document.querySelector('[data-work-package-id="' + wpId + '"]');
      var editing = row && row.querySelector(".inline-edit--active-field");
      if (editing && tries < 25) {
        tries += 1;
        setTimeout(run, 80);
        return;
      }
      refreshWorkPackage(wpId);
      setTimeout(function () {
        refreshWorkPackage(wpId);
      }, 350);
    };
    setTimeout(run, 80);
  }

  function assignToWorkPackage(wpId, p) {
    return fetch("/covenant/ad_invite", {
      method: "POST",
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": csrf()
      },
      body: JSON.stringify({
        project_id: projectId(),
        login: p.login || undefined,
        user_id: p.userId || undefined,
        work_package_id: String(wpId)
      })
    }).then(function (r) {
      return r.json();
    }).then(function () {
      scheduleExecutorRefresh(wpId);
    }).catch(function () {});
  }

  function flushPendingToNewRows() {
    pendingInvites = pendingInvites.filter(function (p) {
      return Date.now() - (p.at || 0) < 120000;
    });
    if (!pendingInvites.length) return;
    var fresh = [];
    document.querySelectorAll("[data-work-package-id]").forEach(function (el) {
      var id = el.getAttribute("data-work-package-id") || "";
      if (/^\d+$/.test(id) && !knownWpIds[id]) fresh.push(id);
    });
    if (!fresh.length) return;
    var wpId = fresh[fresh.length - 1];
    fresh.forEach(function (id) {
      knownWpIds[id] = true;
    });
    var batch = pendingInvites.slice();
    pendingInvites = [];
    createRowSeen = false;
    createRowGoneAt = null;
    knownWpIdsFrozen = false;
    batch.forEach(function (p) {
      assignToWorkPackage(wpId, p);
    });
  }

  function executorsCfName() {
    rememberCfFromDom();
    var meta = document.querySelector('meta[name="covenant-executors-cf"]');
    if (meta && meta.content) return meta.content;
    var keys = Object.keys(learnedCf);
    return keys[0] || "";
  }

  function patchCreatePayload(body) {
    var cf = executorsCfName();
    if (!cf || !pendingInvites.length) return body;
    var data;
    try {
      data = typeof body === "string" ? JSON.parse(body) : body;
    } catch (e) {
      return body;
    }
    if (!data || typeof data !== "object") return body;
    data._links = data._links || {};
    var existing = data._links[cf];
    var arr = existing ? [].concat(existing) : [];
    var seen = {};
    arr.forEach(function (l) {
      if (l && l.href) seen[l.href] = true;
    });
    pendingInvites.forEach(function (p) {
      if (!p.userId) return;
      var href = "/api/v3/users/" + p.userId;
      if (!seen[href]) {
        seen[href] = true;
        arr.push({ href: href });
      }
    });
    if (arr.length) data._links[cf] = arr;
    return typeof body === "string" ? JSON.stringify(data) : data;
  }

  function isWpCreateUrl(url) {
    return /\/api\/v3\/work_packages\/?(\?|$)/.test(String(url || ""));
  }

  var origFetch = window.fetch;
  window.fetch = function (input, init) {
    var url = "";
    var method = "GET";
    var body;
    try {
      url = typeof input === "string" ? input : (input && input.url) || "";
      method = ((init && init.method) || (input && input.method) || "GET").toUpperCase();
      body = init && init.body;
      if (method === "POST" && isWpCreateUrl(url) && pendingInvites.length) {
        init = Object.assign({}, init || {});
        if (init.body) init.body = patchCreatePayload(init.body);
        body = init.body;
      }
    } catch (e) {}
    var req = origFetch.apply(this, arguments);
    try {
      var wpId = wpIdFromApiUrl(url);
      if ((method === "PATCH" || method === "POST") && wpId && bodyHasExecutorsCf(body)) {
        return req.then(function (res) {
          scheduleExecutorRefresh(wpId);
          return res;
        });
      }
    } catch (e) {}
    return req;
  };

  var origXhrOpen = XMLHttpRequest.prototype.open;
  var origXhrSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url) {
    this.__covenantMethod = method;
    this.__covenantUrl = url;
    return origXhrOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function (body) {
    try {
      var method = String(this.__covenantMethod || "").toUpperCase();
      var url = this.__covenantUrl;
      if (method === "POST" && isWpCreateUrl(url) && pendingInvites.length && body) {
        body = patchCreatePayload(body);
      }
      var wpId = wpIdFromApiUrl(url);
      if ((method === "PATCH" || method === "POST") && wpId && bodyHasExecutorsCf(body)) {
        this.addEventListener("load", function () {
          scheduleExecutorRefresh(wpId);
        });
      }
    } catch (e) {}
    return origXhrSend.call(this, body);
  };

  function startPendingWatch() {
    if (pendingWatch) return;
    pendingWatch = setInterval(function () {
      noteInlineCreateLifecycle();
      harvestInlineCreateExecutors();
      flushPendingToNewRows();
      dropStalePending();
      if (!pendingInvites.length && !document.querySelector(".wp-inline-create-row") && !createRowSeen) {
        clearInterval(pendingWatch);
        pendingWatch = null;
      }
    }, 300);
  }

  function emitStockInviteClose(userId) {
    document.dispatchEvent(
      new CustomEvent("dialog:close", {
        bubbles: true,
        detail: {
          dialog: { id: "user-invitation-dialog" },
          submitted: true,
          additional: { user_id: String(userId) }
        }
      })
    );
  }

  function putUserIntoField(userHal, login, name, userId) {
    if (isUnsavedInlineRow()) {
      queuePendingExecutor({ userId: userId, login: login, name: name });
      if (userHal) {
        var sel =
          (lastFieldHost && lastFieldHost.querySelector && lastFieldHost.querySelector("ng-select, .ng-select")) ||
          document.querySelector(".wp-inline-create-row ng-select, .wp-inline-create-row .ng-select");
        if (sel) {
          walkNgContext(sel, function (v) {
            if (v && v.resource && v.name && /customField/.test(String(v.name))) {
              var cur = v.resource[v.name];
              var arr = cur ? [].concat(cur) : [];
              arr.push(userHal);
              v.resource[v.name] = arr;
              if (v.cdRef && v.cdRef.markForCheck) v.cdRef.markForCheck();
              return true;
            }
            return false;
          });
        }
      }
      return;
    }

    if (userId) emitStockInviteClose(userId);

    var roots = [];
    if (lastFieldHost) {
      roots.push(lastFieldHost);
      if (lastFieldHost.closest) {
        roots.push(lastFieldHost.closest(".inline-edit--active-field, op-user-autocompleter, td, form"));
      }
    }
    document.querySelectorAll(".inline-edit--active-field, op-user-autocompleter").forEach(function (el) {
      roots.push(el);
    });

    var emitted = false;
    roots.forEach(function (root) {
      if (emitted || !root) return;
      walkNgContext(root, function (v) {
        if (!v) return false;
        if (v.opInviteUserDialogService && v.opInviteUserDialogService.close) {
          v.opInviteUserDialogService.close.emit(userHal);
          emitted = true;
          return true;
        }
        if (v.opInviteUserModalService && v.opInviteUserModalService.close) {
          v.opInviteUserModalService.close.emit(userHal);
          emitted = true;
          return true;
        }
        if (v.userInvited && v.userInvited.emit) {
          v.userInvited.emit(userHal);
          emitted = true;
          return true;
        }
        if (typeof v.onModelChange === "function") {
          v.onModelChange(userHal);
          emitted = true;
          return true;
        }
        if (typeof v.onCreate === "function") {
          v.onCreate(userHal);
          emitted = true;
          return true;
        }
        if (typeof v.onNewValueAdded === "function") {
          v.onNewValueAdded(userHal);
          emitted = true;
          return true;
        }
        if (v.resource && v.name && v.handler && v.handler.handleUserSubmit) {
          var cur = v.resource[v.name];
          var arr = cur ? [].concat(cur) : [];
          arr.push(userHal);
          v.resource[v.name] = arr;
          if (v.cdRef && v.cdRef.markForCheck) v.cdRef.markForCheck();
          v.handler.handleUserSubmit();
          emitted = true;
          return true;
        }
        return false;
      });
    });

    if (!emitted) pickExecutorByTyping(login, name);
    if (workPackageId()) scheduleExecutorRefresh(workPackageId());
  }

  function pickExecutorByTyping(login, name) {
    var sel =
      (lastFieldHost && lastFieldHost.querySelector("ng-select, .ng-select")) ||
      (lastFieldHost && lastFieldHost.closest && lastFieldHost.closest("ng-select, .ng-select")) ||
      document.querySelector(".ng-select.ng-select-opened, ng-select.ng-select-opened");
    if (!sel) return;
    var box = sel.querySelector(".ng-select-container") || sel;
    box.click();
    setTimeout(function () {
      var input = sel.querySelector("input");
      if (!input) return;
      var desc = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value");
      if (desc && desc.set) desc.set.call(input, login);
      else input.value = login;
      input.dispatchEvent(new Event("input", { bubbles: true }));
      var tries = 15;
      var tick = function () {
        var panel = document.querySelector(".ng-dropdown-panel");
        var opts = panel ? panel.querySelectorAll(".ng-option") : [];
        var needle = (login + " " + (name || "")).toLowerCase();
        for (var i = 0; i < opts.length; i++) {
          var t = (opts[i].textContent || "").toLowerCase();
          if (t && needle.split(" ").some(function (p) { return p && t.indexOf(p) >= 0; })) {
            opts[i].click();
            return;
          }
        }
        if (--tries > 0) setTimeout(tick, 200);
      };
      tick();
    }, 120);
  }

  function applyInvitedUser(data) {
    var login = data.login;
    var name = data.name;
    var id = data.user_id;
    var ctxPromise =
      window.OpenProject && OpenProject.getPluginContext
        ? OpenProject.getPluginContext()
        : Promise.reject();
    ctxPromise
      .then(function (plugin) {
        plugin.runInZone(function () {
          plugin.services.apiV3Service.users.id(String(id)).get().subscribe(
            function (user) {
              putUserIntoField(user, login, name, id);
            },
            function () {
              pickExecutorByTyping(login, name);
            }
          );
        });
      })
      .catch(function () {
        pickExecutorByTyping(login, name);
      });
  }

  function invite(login) {
    setStatus("Добавляем…");
    fetch("/covenant/ad_invite", {
      method: "POST",
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": csrf()
      },
      body: JSON.stringify({
        project_id: projectId(),
        login: login,
        work_package_id: workPackageId() || undefined
      })
    })
      .then(function (r) {
        return r.json().then(function (data) {
          return { ok: r.ok, data: data };
        });
      })
      .then(function (res) {
        if (!res.ok || res.data.error) {
          setStatus(res.data.error || "Не удалось пригласить.", true);
          return;
        }
        setStatus(res.data.message || "Добавлен.");
        closeModal();
        applyInvitedUser(res.data);
        if (workPackageId()) scheduleExecutorRefresh(workPackageId());
      })
      .catch(function () {
        setStatus("Не удалось пригласить.", true);
      });
  }

  function isInviteButton(el) {
    if (!el || !el.closest) return null;
    return (
      el.closest("[data-covenant-ad-invite-field]") ||
      el.closest("[data-covenant-ad-invite-dd]") ||
      el.closest("[data-covenant-ad-invite-cell]") ||
      el.closest("op-invite-user-button") ||
      el.closest('[data-test-selector="op-invite-user-button"]') ||
      el.closest(".op-invite-user-button")
    );
  }

  var learnedCf = {};

  function rememberCfFromDom() {
    var meta = document.querySelector('meta[name="covenant-executors-cf"]');
    if (meta && meta.content) learnedCf[meta.content] = true;
    document.querySelectorAll("label").forEach(function (lab) {
      if (!/Исполнител/.test(lab.textContent || "")) return;
      var fr = lab.getAttribute("for") || "";
      var m = fr.match(/customField\d+/);
      if (m) learnedCf[m[0]] = true;
      var wrap = lab.closest(".wp-table--cell-container, .inline-edit--active-field, td, .attributes-key-value");
      if (wrap) {
        var cm = ((wrap.className || "").toString()).match(/customField\d+/);
        if (cm) learnedCf[cm[0]] = true;
      }
    });
  }

  function classHasExecutor(cls) {
    var s = " " + (cls || "").toString() + " ";
    if (/\sresponsible\s/.test(s)) return false;
    rememberCfFromDom();
    var name;
    for (name in learnedCf) {
      if (learnedCf[name] && s.indexOf(" " + name + " ") !== -1) return true;
      var n = String(name).replace(/^customField/i, "");
      if (n && /^\d+$/.test(n) && s.indexOf(" cf_" + n + " ") !== -1) return true;
    }
    return false;
  }

  function isTableCell(el) {
    return !!(el && el.closest && el.closest("td, table.work-package-table, .wp-table--cell-container, .work-packages-split-view--tabletimeline-side"));
  }

  function isExecutorsContext(el) {
    if (!el || !el.closest) return false;
    if (isPriorityContext(el)) return false;
    rememberCfFromDom();

    var ns = el.closest("ng-select, .ng-select");
    var nsId = (ns && ns.id) || el.id || "";
    if (nsId) {
      var forLab = document.querySelector('label[for="' + nsId + '"]');
      if (forLab && /Исполнител/.test(forLab.textContent || "")) return true;
    }

    // Только ячейка/поле, не form — иначе лейбл «Исполнители» в шапке таблицы
    // красит приоритет/статус как executors.
    var scope = el.closest(
      ".inline-edit--active-field, .wp-table--cell-container, .attributes-key-value, .spot-form-field, td"
    );
    var i;
    if (scope && !isPriorityContext(scope)) {
      var labs = scope.querySelectorAll ? scope.querySelectorAll("label") : [];
      for (i = 0; i < labs.length; i++) {
        if (/Исполнител/.test(labs[i].textContent || "")) return true;
      }
    }

    var kv = el.closest(".attributes-key-value");
    if (kv) {
      var key = kv.querySelector(".attributes-key-value--key, label");
      if (key && /Исполнител/.test(key.textContent || "")) return true;
    }

    var node = el;
    for (i = 0; i < 14 && node && node !== document.body; i++) {
      if (isPriorityContext(node)) return false;
      if (classHasExecutor(node.className)) return true;
      node = node.parentElement;
    }
    return false;
  }

  function panelForSelect(sel) {
    if (!sel) return null;
    var input = sel.querySelector("input[aria-controls], [aria-controls]");
    var id = input && input.getAttribute("aria-controls");
    if (id) {
      var byId = document.getElementById(id);
      if (byId) return byId;
    }
    return sel.querySelector(".ng-dropdown-panel, ng-dropdown-panel");
  }

  function activeExecutorSelect() {
    var nodes = document.querySelectorAll("ng-select.ng-select-opened, .ng-select.ng-select-opened, ng-select.ng-select-focused, .ng-select.ng-select-focused");
    var i;
    var s;
    for (i = 0; i < nodes.length; i++) {
      if (isExecutorsContext(nodes[i])) return nodes[i];
    }
    var ae = document.activeElement;
    if (ae && ae.closest) {
      s = ae.closest("ng-select, .ng-select");
      if (s && isExecutorsContext(s)) return s;
    }
    if (lastFieldHost) {
      s =
        (lastFieldHost.querySelector && lastFieldHost.querySelector("ng-select, .ng-select")) ||
        (lastFieldHost.closest && lastFieldHost.closest("ng-select, .ng-select"));
      if (s && isExecutorsContext(s)) return s;
    }
    return null;
  }

  function selectForPanel(panel) {
    if (!panel) return null;
    var id = panel.id || panel.getAttribute("id");
    if (id) {
      var owner = document.querySelector('[aria-owns="' + id + '"], [aria-controls="' + id + '"]');
      if (owner) {
        var s = owner.closest ? owner.closest("ng-select, .ng-select") : null;
        return s || owner;
      }
    }
    return null;
  }

  function inWorkPackageTable(el) {
    return !!(el && el.closest && el.closest(".wp-table--cell-container, .wp-inline-create-row, table.work-package-table, .work-packages-split-view--tabletimeline-side"));
  }

  function makeFieldButton(host) {
    var btn = document.createElement("button");
    btn.type = "button";
    btn.setAttribute("data-covenant-ad-invite-field", "1");
    btn.className = "covenant-ad-invite__field-btn";
    btn.innerHTML =
      '<svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 8a3 3 0 1 0 0-6 3 3 0 0 0 0 6Zm-5 6.5c0-2.5 2.2-4.5 5-4.5.4 0 .8 0 1.2.1A4.5 4.5 0 0 0 8 14c-1.4 0-2.6-.3-3.5-.9A4.7 4.7 0 0 1 3 14.5ZM14 9h-1v1h-1v1h1v1h1v-1h1v-1h-1V9Z"/></svg>' +
      "<span>Пригласить</span>";
    btn.addEventListener("click", function (e) {
      e.preventDefault();
      e.stopPropagation();
      lastFieldHost = host;
      var display = host.querySelector(".inline-edit--display-field, .inline-edit--display-field-label");
      if (display) display.click();
      openModal();
    });
    return btn;
  }

  function isPriorityContext(el) {
    if (!el || !el.closest) return false;
    if (
      el.closest(
        "td.priority, .wp-table--cell-td.priority, .inline-edit--active-field.priority, .wp-table--cell-container.priority"
      )
    ) {
      return true;
    }
    var node = el;
    var i;
    for (i = 0; i < 14 && node && node !== document.body; i++) {
      if (/(^|\s)priority(\s|$)/.test((node.className || "").toString())) return true;
      node = node.parentElement;
    }
    return false;
  }

  function executorEditorHosts() {
    var cf = executorsCfName();
    var seen = [];
    var add = function (el) {
      if (!el || seen.indexOf(el) !== -1) return;
      seen.push(el);
    };
    if (cf) {
      document
        .querySelectorAll(
          ".inline-edit--active-field." +
            cf +
            ", td." +
            cf +
            ".-editing, .wp-table--cell-td." +
            cf +
            ".-editing, td." +
            cf +
            " .inline-edit--active-field"
        )
        .forEach(add);
    }
    document.querySelectorAll(".inline-edit--active-field, td.-editing").forEach(function (el) {
      if (!isPriorityContext(el) && isExecutorsContext(el)) add(el);
    });
    return seen;
  }

  function attachActiveExecutorInvite() {
    var seenSel = [];
    executorEditorHosts().forEach(function (host) {
      if (!inWorkPackageTable(host) && !host.closest(".wp-inline-create-row")) return;
      if (isPriorityContext(host) || isResponsibleContext(host) || !isExecutorsContext(host)) return;
      var sel = host.querySelector("ng-select, .ng-select");
      if (!sel || seenSel.indexOf(sel) !== -1) return;
      seenSel.push(sel);
      if (sel.parentNode && sel.parentNode.querySelector("[data-covenant-ad-invite-cell]")) return;
      var btn = makeDropdownInviteButton(host);
      btn.removeAttribute("data-covenant-ad-invite-dd");
      btn.setAttribute("data-covenant-ad-invite-cell", "1");
      btn.className = "covenant-ad-invite__cell-btn";
      sel.parentNode.insertBefore(btn, sel.nextSibling);
    });
    syncCellInviteVisibility();
  }

  function isResponsibleContext(el) {
    var node = el;
    var i;
    for (i = 0; i < 12 && node && node !== document.body; i++) {
      if (/\sresponsible\s/.test(" " + (node.className || "") + " ")) return true;
      node = node.parentElement;
    }
    return false;
  }

  function dropdownHasInvite() {
    var panels = dropdownPanels();
    var i;
    for (i = 0; i < panels.length; i++) {
      if (panels[i].querySelector("[data-covenant-ad-invite-dd]")) return true;
    }
    return false;
  }

  function syncCellInviteVisibility() {
    var hide = dropdownHasInvite();
    document.querySelectorAll("[data-covenant-ad-invite-cell]").forEach(function (btn) {
      btn.hidden = hide;
    });
  }

  function attachToTableEdit() {
    attachActiveExecutorInvite();
  }

  function attachToWrap(wrap) {
    if (!wrap || isTableCell(wrap)) return;
    var root = wrap.closest(".attributes-key-value") || wrap.closest(".spot-form-field");
    if (!root || root.querySelector("[data-covenant-ad-invite-field]")) return;
    if (!isExecutorsContext(root)) return;
    var value =
      root.querySelector(".attributes-key-value--value-container, .attributes-key-value--value, .spot-form-field--input") ||
      root;
    var btn = makeFieldButton(root);
    btn.classList.add("covenant-ad-invite__field-btn--under");
    value.appendChild(btn);
  }

  function makeDropdownInviteButton(host) {
    var btn = document.createElement("button");
    btn.type = "button";
    btn.setAttribute("data-covenant-ad-invite-dd", "1");
    btn.className = "covenant-ad-invite__dd-btn";
    btn.innerHTML =
      '<svg viewBox="0 0 16 16" width="14" height="14" fill="currentColor" aria-hidden="true"><path d="M8 8a3 3 0 1 0 0-6 3 3 0 0 0 0 6Zm-5 6.5c0-2.5 2.2-4.5 5-4.5.4 0 .8 0 1.2.1A4.5 4.5 0 0 0 8 14c-1.4 0-2.6-.3-3.5-.9A4.7 4.7 0 0 1 3 14.5ZM14 9h-1v1h-1v1h1v1h1v-1h1v-1h-1V9Z"/></svg>' +
      "<span>Пригласить из AD</span>";
    btn.addEventListener("click", function (e) {
      e.preventDefault();
      e.stopPropagation();
      lastFieldHost =
        (host &&
          host.closest &&
          host.closest(
            "op-user-autocompleter, op-autocompleter, .inline-edit--active-field, .spot-form-field, .attributes-key-value, .wp-edit-field, td, .wp-table--cell-container"
          )) ||
        host;
      openModal();
    });
    return btn;
  }

  function injectDropdownFooter(panel, openedHint) {
    if (!panel || panel.querySelector("[data-covenant-ad-invite-dd]")) return;
    var opened = openedHint || selectForPanel(panel);
    if (!opened || isPriorityContext(opened) || !isExecutorsContext(opened)) return;
    var table = inWorkPackageTable(opened) || inWorkPackageTable(lastFieldHost);
    if (document.documentElement.classList.contains("covenant-wp-create") && !table) return;
    var btn = makeDropdownInviteButton(opened);
    var footer = panel.querySelector(".ng-dropdown-footer");
    if (footer) footer.appendChild(btn);
    else panel.appendChild(btn);
    syncCellInviteVisibility();
  }

  function injectOpenedSelects() {
    document.querySelectorAll("ng-select.ng-select-opened, .ng-select.ng-select-opened").forEach(function (sel) {
      if (!isExecutorsContext(sel)) return;
      var panel = panelForSelect(sel);
      if (panel) injectDropdownFooter(panel, sel);
    });
  }

  function dropdownPanels() {
    return document.querySelectorAll(".ng-dropdown-panel, ng-dropdown-panel");
  }

  function scanExecutorFields() {
    attachToTableEdit();
    document
      .querySelectorAll(
        ".spot-form-field, .attributes-key-value, .inline-edit--container, .wp-edit-field, op-user-autocompleter"
      )
      .forEach(attachToWrap);
    injectOpenedSelects();
    dropdownPanels().forEach(function (panel) {
      injectDropdownFooter(panel);
    });
  }

  var pumping = false;
  function pumpPanels() {
    attachToTableEdit();
    injectOpenedSelects();
    var panels = dropdownPanels();
    var i;
    for (i = 0; i < panels.length; i++) injectDropdownFooter(panels[i]);
    syncCellInviteVisibility();
    var open = document.querySelector(
      "ng-select.ng-select-opened, .ng-select.ng-select-opened, .ng-dropdown-panel, ng-dropdown-panel"
    );
    if (open || panels.length) {
      pumping = true;
      requestAnimationFrame(pumpPanels);
    } else {
      pumping = false;
    }
  }

  var burstId = null;
  function startPump() {
    if (!pumping) {
      pumping = true;
      requestAnimationFrame(pumpPanels);
    }
    if (burstId) clearInterval(burstId);
    var n = 0;
    burstId = setInterval(function () {
      attachToTableEdit();
      injectOpenedSelects();
      dropdownPanels().forEach(function (panel) {
        injectDropdownFooter(panel);
      });
      if (++n > 24) {
        clearInterval(burstId);
        burstId = null;
      }
    }, 50);
  }

  function rememberExecutorHost(el) {
    if (!el || !el.closest) return false;
    var host = el.closest(
      "td, .wp-table--cell-container, op-user-autocompleter, op-autocompleter, ng-select, .ng-select, .inline-edit--container, .wp-inline-create-row, .wp-inline-create--cell"
    );
    if (host && isExecutorsContext(host)) {
      lastFieldHost = host;
      return true;
    }
    return false;
  }

  document.addEventListener(
    "pointerdown",
    function (e) {
      var cell =
        e.target &&
        e.target.closest &&
        e.target.closest(".wp-table--cell-container, .inline-edit--active-field, ng-select, .ng-select");
      rememberExecutorHost(e.target);
      if (cell) startPump();
    },
    true
  );

  document.addEventListener(
    "click",
    function (e) {
      if (isInviteButton(e.target)) {
        lastFieldHost =
          e.target.closest(
            "op-user-autocompleter, op-autocompleter, .inline-edit--active-field, .spot-form-field, .attributes-key-value, .wp-edit-field, td, .wp-table--cell-container"
          ) || e.target;
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation();
        openModal();
        return;
      }
      if (rememberExecutorHost(e.target)) {
        startPump();
        scanSoon();
      }
      var opt = e.target.closest && e.target.closest(".ng-option");
      if (opt && document.querySelector(".wp-inline-create-row")) {
        noteInlineCreateLifecycle();
        walkNgContext(opt, function (v) {
          if (!v) return false;
          var href = (v.href || (v.$links && v.$links.self && v.$links.self.href) || "") + "";
          var id = v.id || (href && /\/users\/(\d+)/.test(href) && RegExp.$1);
          if (id && /^\d+$/.test(String(id)) && (v.login || href.indexOf("/users/") !== -1)) {
            queuePendingExecutor({ userId: id, login: v.login, name: v.name });
            return true;
          }
          return false;
        });
        [0, 30, 80, 160].forEach(function (ms) {
          setTimeout(harvestInlineCreateExecutors, ms);
        });
      }
      if (
        e.target.closest(".wp-inline-create-row .icon-cancel") ||
        e.target.closest(".wp-inline-create--cancel") ||
        e.target.closest(".wp-table--cancel-inline-create") ||
        e.target.closest("a.wp-inline-create--cancel")
      ) {
        clearPendingCreate();
      }
    },
    true
  );

  var scanTimer = null;
  function scheduleScan() {
    clearTimeout(scanTimer);
    scanTimer = setTimeout(scanExecutorFields, 80);
  }

  function scanSoon() {
    scanExecutorFields();
    retryTimers.forEach(clearTimeout);
    retryTimers = [16, 50, 120, 250, 400].map(function (ms) {
      return setTimeout(scanExecutorFields, ms);
    });
  }

  function mutationLooksLikeDropdown(mutations) {
    for (var i = 0; i < mutations.length; i++) {
      var nodes = mutations[i].addedNodes;
      for (var j = 0; j < nodes.length; j++) {
        var n = nodes[j];
        if (!n || n.nodeType !== 1) continue;
        if (n.classList && n.classList.contains("ng-dropdown-panel")) return true;
        if (n.tagName && String(n.tagName).toLowerCase() === "ng-dropdown-panel") return true;
        if (n.querySelector && n.querySelector(".ng-dropdown-panel, ng-dropdown-panel")) return true;
      }
    }
    return false;
  }

  // ng-select на последнем крестике отдаёт null, сеттер падает до записи в changeset.
  // В PATCH уходит старый список, сохранение «успешное», человек остаётся.
  document.addEventListener(
    "click",
    function (e) {
      var t = e.target;
      if (!t || !t.closest || !t.closest(".ng-value-icon")) return;
      var host = t.closest(".inline-edit--active-field, td.-editing, .inline-edit--container, .attributes-key-value");
      if (!host || !isExecutorsContext(host)) return;
      setTimeout(function () {
        var sel = host.querySelector("ng-select, .ng-select");
        if (!sel || sel.querySelector(".ng-value")) return;
        walkNgContext(sel, function (v) {
          if (!v || !v.resource || !v.name || !/customField/i.test(String(v.name))) return false;
          v.resource[v.name] = [];
          return true;
        });
      }, 0);
    },
    true
  );

  injectStyles();
  markCreatePage();
  window.addEventListener("popstate", markCreatePage);
  var _push = history.pushState;
  history.pushState = function () {
    var ret = _push.apply(this, arguments);
    markCreatePage();
    return ret;
  };
  var _replace = history.replaceState;
  history.replaceState = function () {
    var ret = _replace.apply(this, arguments);
    markCreatePage();
    return ret;
  };

  var obs = new MutationObserver(function (mutations) {
    markCreatePage();
    attachToTableEdit();
    if (document.querySelector(".wp-inline-create-row")) noteInlineCreateLifecycle();
    if (mutationLooksLikeDropdown(mutations)) {
      startPump();
      scanSoon();
    } else {
      scheduleScan();
    }
  });
  if (document.body) {
    obs.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["class"] });
    scheduleScan();
  } else {
    document.addEventListener("DOMContentLoaded", function () {
      injectStyles();
      obs.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["class"] });
      scheduleScan();
    });
  }
})();
