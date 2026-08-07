/* Forecast widget.
 *
 * The site and the api share an origin - CloudFront routes /api/* to API
 * Gateway - so a relative path is all that is needed. window.API_BASE stays
 * supported for local development against a remote api.
 */
(function () {
  "use strict";

  var API = (window.API_BASE || "") + "/api";

  var $station = document.getElementById("station");
  var $date = document.getElementById("date");
  var $hour = document.getElementById("hour");
  var $go = document.getElementById("go");
  var $out = document.getElementById("out");
  var $note = document.getElementById("note");

  // The widget is optional furniture on the page; bail rather than throw if
  // this script is loaded somewhere without it (e.g. error.html).
  if (!$station || !$go) return;

  function show(html) {
    $out.innerHTML = html;
  }

  function hourLabel(h) {
    if (h === 0) return "12 AM";
    if (h < 12) return h + " AM";
    if (h === 12) return "12 PM";
    return h - 12 + " PM";
  }

  for (var h = 0; h < 24; h++) {
    var pad = String(h).padStart(2, "0");
    $hour.add(new Option(pad + ":00 · " + hourLabel(h), h));
  }
  $hour.value = 17;

  /* The model is trained on prior-year history, so it only serves the year the
   * image was built for. Clamping the date input avoids a 400 the user cannot
   * otherwise anticipate. */
  function init() {
    fetch(API + "/stations")
      .then(function (r) {
        if (!r.ok) throw new Error("stations: HTTP " + r.status);
        return r.json();
      })
      .then(function (data) {
        $station.innerHTML = "";
        data.stations.forEach(function (s) {
          $station.add(new Option(s.name, s.id));
        });

        $date.min = data.target_year + "-01-01";
        $date.max = data.target_year + "-12-31";
        $date.value = data.target_year + "-07-19";

        $note.textContent =
          data.stations.length +
          " stations · forecasts for " +
          data.target_year +
          ", based on " +
          data.history_year +
          " demand patterns.";
        $go.disabled = false;
      })
      .catch(function (err) {
        $station.innerHTML = "<option>unavailable</option>";
        show('<p class="text-danger small mb-0">Could not load stations. ' + err.message + "</p>");
      });
  }

  function forecast() {
    $go.disabled = true;
    show('<div class="spinner-border text-primary" role="status"><span class="visually-hidden">Loading…</span></div>');

    var body = {
      station_id: Number($station.value),
      date: $date.value,
      hour: Number($hour.value)
    };

    fetch(API + "/forecast", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body)
    })
      .then(function (r) {
        return r.json().then(function (data) {
          // The api reports its own validation errors in `error`; surface
          // those rather than a generic failure, since they say what to change.
          if (!r.ok) throw new Error(data.error || "HTTP " + r.status);
          return data;
        });
      })
      .then(function (data) {
        var n = data.predictions[0];
        var name = $station.options[$station.selectedIndex].text;
        show(
          '<div class="forecast-value">' + n.toFixed(1) + "</div>" +
          '<div class="forecast-unit">trips expected · ' + name + "</div>"
        );
      })
      .catch(function (err) {
        show('<p class="text-danger small mb-0">' + err.message + "</p>");
      })
      .then(function () {
        $go.disabled = false;
      });
  }

  $go.addEventListener("click", forecast);
  init();
})();
