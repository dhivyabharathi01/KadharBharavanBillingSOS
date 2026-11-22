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
      amount <= 0 ||
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
  const isAndroid = /Android/i.test(navigator.userAgent);
  const isAppleMobile = /iPhone|iPad|iPod/i.test(navigator.userAgent);

  if (isAndroid) {
    const intentUrl = `intent://${payment.host}${payment.pathname}${payment.search}#Intent;scheme=upi;action=android.intent.action.VIEW;category=android.intent.category.BROWSABLE;end`;
    payNow.href = intentUrl;
    payNow.addEventListener('click', () => {
      setTimeout(() => {
        if (document.hasFocus()) location.href = payment.href;
      }, 1500);
    });
  } else {
    payNow.href = payment.href;
  }
  payNow.hidden = false;

  if (isAndroid) {
    status.textContent = 'Tap Pay now to open a UPI app.';
  } else if (isAppleMobile) {
    status.textContent = 'Tap Pay now to open a compatible UPI app.';
  } else {
    status.textContent = 'Open this link on a phone with a UPI app.';
  }
})();
