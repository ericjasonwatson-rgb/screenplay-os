(async () => {
  document.getElementById('year').textContent = new Date().getFullYear();
  try {
    const response = await fetch('release.json', {cache: 'no-store'});
    if (!response.ok) throw new Error('release config unavailable');
    const release = await response.json();
    document.getElementById('version').textContent = `Version ${release.version} (${release.build})`;
    document.getElementById('release-date').textContent = release.releaseDate || 'Release date pending';
    if (release.published) {
      const button = document.getElementById('download');
      button.href = release.downloadUrl;
      button.removeAttribute('aria-disabled');
      document.getElementById('download-state').textContent = 'Direct download from screenplayos.com';
      document.getElementById('compatibility').textContent = 'Universal build for Apple Silicon and Intel Macs, macOS 13 or later.';
    }
  } catch (_) {
    document.getElementById('download-state').textContent = 'Download information is temporarily unavailable';
  }
})();
