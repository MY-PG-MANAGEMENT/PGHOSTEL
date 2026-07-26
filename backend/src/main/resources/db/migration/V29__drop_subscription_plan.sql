-- Drops the subscription plan master along with the Plans admin screen and its
-- /api/super-admin/plans endpoints.
--
-- The table was a pricing catalogue nothing ever consumed: no @Entity mapped it, no join
-- read it, and its only FK dependent (plan_feature) was already dropped in V24. Billing
-- prices come from property_sharing_price, not from here.
--
-- Note this is NOT the `subscription` table (V1), which is still mapped by the Subscription
-- entity and keeps its plan_code as a plain string. If plans are reintroduced, add a fresh
-- migration rather than editing this one.

DROP TABLE IF EXISTS subscription_plan;
