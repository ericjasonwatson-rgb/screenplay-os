(() => {
  document.getElementById('year').textContent = new Date().getFullYear();
  const checksumButton = document.getElementById('copy-checksum');
  checksumButton?.addEventListener('click', async () => {
    const checksum = document.getElementById('dmg-checksum').textContent.trim();
    try {
      await navigator.clipboard.writeText(checksum);
      document.getElementById('checksum-status').textContent = 'Checksum copied.';
    } catch (_) {
      document.getElementById('checksum-status').textContent = 'Select the checksum above to copy it.';
    }
  });

  const copy = {
    success: 'Check your inbox. Confirm your email to open the Mac download.',
    duplicate: 'This address is already on the list. Check your inbox for the confirmation email.',
    error: 'Signup is unavailable. Please write to hello@screenplayos.com.'
  };
  document.querySelectorAll('.signup-form').forEach(form => {
    form.addEventListener('submit', async event => {
      event.preventDefault();
      const status = form.querySelector('.form-status');
      const button = form.querySelector('button[type=submit]');
      if (!form.reportValidity()) return;
      button.disabled = true;
      status.textContent = 'Submitting…';
      status.dataset.kind = '';
      try {
        const response = await fetch(form.action, {
          method: 'POST',
          mode: 'cors',
          headers: {'Accept': 'application/json'},
          body: new FormData(form)
        });
        const result = await response.json();
        const kind = result.status === 'success' || result.status === 'duplicate' ? result.status : 'error';
        status.textContent = copy[kind];
        status.dataset.kind = kind;
        if (kind === 'success') form.reset();
      } catch (_) {
        status.textContent = copy.error;
        status.dataset.kind = 'error';
      } finally {
        button.disabled = false;
      }
    });
  });
})();
