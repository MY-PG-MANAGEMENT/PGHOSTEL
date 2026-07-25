-- V27: per-org checkout grace window for the auto-generated next-cycle invoice.
--
-- The scheduler raises a tenant's monthly invoice `invoice_lead_days` BEFORE the
-- due date, so a tenant who checks out around that date is left holding an invoice
-- for a month they will not stay. `checkout_grace_days` is how many days AFTER the
-- due date that invoice still counts as "not consumed": checking out on or before
-- (due_date + checkout_grace_days) hard-deletes it instead of asking the owner to
-- pay or write it off. Checking out later keeps the invoice payable as normal.
--
-- Default 2: with the default lead of 1 day, an invoice due on the 26th is dropped
-- for a checkout on the 25th, 26th, 27th or 28th.
--
-- Invoices that already carry a payment (or a security-deposit line) are never
-- dropped — see billing/CheckoutInvoiceService.
--
ALTER TABLE organization_billing_config
    ADD COLUMN checkout_grace_days INT NOT NULL DEFAULT 2 AFTER invoice_lead_days;
