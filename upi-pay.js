(() => {
  const status = document.getElementById('paymentStatus');
  const details = document.getElementById('paymentDetails');
  const payNow = document.getElementById('payNow');
  const encodedUri = new URLSearchParams(location.search).get('p') || '';

  let payment;
  try {
    const base64 = encodedUri.replace(/-/g, '+').replace(/_/g, '/');
    const rawUri = atob(base64.padEnd(Math.ceil(base64.length / 4) * 4, '='));
    payment = new URL(rawUri);
    const amount = Number(payment.searchParams.get('am'));
    if (
      payment.protocol !== 'upi:' ||
      payment.hostname !== 'pay' ||
      !payment.searchParams.get('pa') ||
      !Number.isFinite(amount) ||
      amount < 0 ||
      payment.searchParams.get('cu') !== 'INR'
    ) {
      throw new Error('Invalid UPI payment link');
    }
  } catch {
    status.textContent = 'This payment link is invalid. Ask the shop for a new bill.';
    return;
  }

  const merchant = payment.searchParams.get('pn') || 'Shop';
  const amount = Number(payment.searchParams.get('am')).toFixed(2);
  details.textContent = `${merchant} · ₹${amount}`;
  payNow.href = payment.href;
  payNow.hidden = false;
  status.textContent = 'Opening a compatible UPI app…';

  if (/Android|iPhone|iPad|iPod/i.test(navigator.userAgent)) {
    setTimeout(() => {
      location.href = payment.href;
      status.textContent = 'If your UPI app did not open, tap Pay now.';
    }, 100);
  } else {
    status.textContent = 'Open this link on a phone with a UPI app.';
  }
})();
