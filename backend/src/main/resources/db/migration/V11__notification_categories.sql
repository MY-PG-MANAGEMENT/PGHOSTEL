INSERT IGNORE INTO notification_category (category_id, name, description, active) VALUES
('RENT_REMINDER',    'Rent Reminders',     'Automated rent due and overdue reminders',          TRUE),
('CHECKOUT_REMINDER','Checkout Reminders', 'Upcoming tenant checkout notifications',            TRUE),
('PAYMENT_RECEIPT',  'Payment Receipts',   'Payment confirmation and receipt notifications',    TRUE),
('CHECK_IN',         'Check-in Welcome',   'New tenant check-in notifications',                 TRUE),
('GENERAL',          'General',            'General system notifications',                      TRUE);
