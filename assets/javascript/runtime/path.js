export function smoothPath(points) {
  const n = points.length;
  if (n === 0) return "";
  if (n === 1) return `M${points[0][0].toFixed(1)} ${points[0][1].toFixed(1)}`;

  const xs = points.map((p) => p[0]);
  const ys = points.map((p) => p[1]);
  const secants = [];
  const slopes = new Array(n);

  for (let i = 0; i < n - 1; i++) {
    secants.push((ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]));
  }

  slopes[0] = secants[0];
  slopes[n - 1] = secants[n - 2];

  for (let i = 1; i < n - 1; i++) {
    slopes[i] = secants[i - 1] * secants[i] <= 0 ? 0 : (secants[i - 1] + secants[i]) / 2;
  }

  for (let i = 0; i < n - 1; i++) {
    if (secants[i] === 0) {
      slopes[i] = 0;
      slopes[i + 1] = 0;
      continue;
    }

    const a = slopes[i] / secants[i];
    const b = slopes[i + 1] / secants[i];
    const magnitude = a * a + b * b;

    if (magnitude > 9) {
      const scale = 3 / Math.sqrt(magnitude);
      slopes[i] = scale * a * secants[i];
      slopes[i + 1] = scale * b * secants[i];
    }
  }

  let d = `M${xs[0].toFixed(1)} ${ys[0].toFixed(1)}`;

  for (let i = 0; i < n - 1; i++) {
    const h = xs[i + 1] - xs[i];
    const c1x = (xs[i] + h / 3).toFixed(1);
    const c1y = (ys[i] + (slopes[i] * h) / 3).toFixed(1);
    const c2x = (xs[i + 1] - h / 3).toFixed(1);
    const c2y = (ys[i + 1] - (slopes[i + 1] * h) / 3).toFixed(1);

    d += `C${c1x} ${c1y} ${c2x} ${c2y} ${xs[i + 1].toFixed(1)} ${ys[i + 1].toFixed(1)}`;
  }

  return d;
}

export function areaPath(line, points, baseY) {
  if (!line || points.length === 0) return "";

  const first = points[0][0].toFixed(1);
  const last = points[points.length - 1][0].toFixed(1);

  return `${line}L${last} ${baseY}L${first} ${baseY}Z`;
}
