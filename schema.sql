/* -----------------------------------------------------------
   TABLYY Database Schema (MySQL 8+)
   - InnoDB engine
   - utf8mb4 charset
   - Includes RBAC, API keys, sessions, QR tokens, audit,
     match logs, payments (online/offline), indexes & triggers
   ----------------------------------------------------------- */

CREATE DATABASE IF NOT EXISTS tablyy CHARACTER SET = 'utf8mb4' COLLATE = 'utf8mb4_unicode_ci';
USE tablyy;

SET sql_mode = 'STRICT_ALL_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';
  
-- Common: ensure InnoDB and default charset
-- ==================================================================

/* ---------------------------
   Restaurants / Tables / Photos
   --------------------------- */
CREATE TABLE restaurants (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(255) NOT NULL,
  phone VARCHAR(50),
  email VARCHAR(255),
  address TEXT,
  service_charge_pct DECIMAL(5,2) DEFAULT 0.00,
  gst_no VARCHAR(100),
  languages JSON,
  is_active TINYINT(1) DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY ux_restaurants_slug (slug)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE tables (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  restaurant_id BIGINT UNSIGNED NOT NULL,
  table_code VARCHAR(64) NOT NULL,   -- e.g., F0T1
  floor_name VARCHAR(64) NULL,
  status ENUM('vacant','occupied') NOT NULL DEFAULT 'vacant',
  max_seats INT UNSIGNED DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY ux_rest_table (restaurant_id, table_code),
  INDEX idx_tables_restaurant_id (restaurant_id),
  CONSTRAINT fk_tables_restaurant FOREIGN KEY (restaurant_id) REFERENCES restaurants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE table_photos (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  table_id BIGINT UNSIGNED NOT NULL,
  s3_path VARCHAR(1024) NOT NULL,
  embedding_vector LONGTEXT NULL,
  is_reference TINYINT(1) DEFAULT 1, -- 1 = used as reference image
  uploaded_by BIGINT UNSIGNED NULL,
  uploaded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_table_photos_table_id (table_id),
  CONSTRAINT fk_table_photos_table FOREIGN KEY (table_id) REFERENCES tables(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- QR tokens for short-URLs
CREATE TABLE qr_tokens (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  restaurant_id BIGINT UNSIGNED NOT NULL,
  table_id BIGINT UNSIGNED NOT NULL,
  token VARCHAR(128) NOT NULL,
  token_type ENUM('short','permanent') DEFAULT 'short',
  expires_at DATETIME NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_qr_token (token),
  UNIQUE KEY ux_qr_token (token),
  CONSTRAINT fk_qr_rest FOREIGN KEY (restaurant_id) REFERENCES restaurants(id) ON DELETE CASCADE,
  CONSTRAINT fk_qr_table FOREIGN KEY (table_id) REFERENCES tables(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Sessions created after AI verification
CREATE TABLE sessions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  table_id BIGINT UNSIGNED NOT NULL,
  session_token VARCHAR(255) NOT NULL,
  match_score FLOAT NULL,
  started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ends_at TIMESTAMP NULL,    -- TTL - when session auto-expires
  ended_at TIMESTAMP NULL,
  active TINYINT(1) NOT NULL DEFAULT 1,
  created_by BIGINT UNSIGNED NULL, -- staff or system id
  INDEX idx_sessions_token (session_token),
  INDEX idx_sessions_table (table_id, active),
  CONSTRAINT fk_sessions_table FOREIGN KEY (table_id) REFERENCES tables(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Match / verification logs (keeps evidence, for fraud detection & audit)
CREATE TABLE match_logs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  table_id BIGINT UNSIGNED NULL,
  session_id BIGINT UNSIGNED NULL,
  match_score FLOAT NULL,
  result ENUM('success','failed','fraud_attempt') NOT NULL,
  user_photo_path VARCHAR(1024) NULL,
  reason VARCHAR(512) NULL,
  detected_by VARCHAR(255) NULL, -- e.g., n8n, vision-api
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_match_logs_table (table_id),
  INDEX idx_match_logs_session (session_id),
  CONSTRAINT fk_match_logs_table FOREIGN KEY (table_id) REFERENCES tables(id) ON DELETE SET NULL,
  CONSTRAINT fk_match_logs_session FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------
-- Menu, Items, Categories
-- ---------------------------
CREATE TABLE menu_categories (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  restaurant_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(255) NOT NULL,
  position INT DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_menu_categories_rest (restaurant_id),
  CONSTRAINT fk_menu_categories_rest FOREIGN KEY (restaurant_id) REFERENCES restaurants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE menu_items (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  restaurant_id BIGINT UNSIGNED NOT NULL,
  category_id BIGINT UNSIGNED NULL,
  name VARCHAR(255) NOT NULL,
  description TEXT NULL,
  price DECIMAL(10,2) NOT NULL,
  cost_price DECIMAL(10,2) NULL,
  image_url VARCHAR(1024) NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  stock INT DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_menu_items_rest (restaurant_id),
  INDEX idx_menu_items_category (category_id),
  CONSTRAINT fk_menu_items_rest FOREIGN KEY (restaurant_id) REFERENCES restaurants(id) ON DELETE CASCADE,
  CONSTRAINT fk_menu_items_cat FOREIGN KEY (category_id) REFERENCES menu_categories(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------
-- Orders, Order Items, Sessions relation
-- ---------------------------
CREATE TABLE orders (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  restaurant_id BIGINT UNSIGNED NOT NULL,
  table_id BIGINT UNSIGNED NOT NULL,
  session_id BIGINT UNSIGNED NULL,
  order_uid VARCHAR(64) NOT NULL, -- human-friendly order id or code
  subtotal DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  tax DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  service_charge DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  discount DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  total DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  payment_status ENUM('pending','paid_online','paid_offline','failed') DEFAULT 'pending',
  status ENUM('pending','accepted','preparing','ready','delivered','cancelled') DEFAULT 'pending',
  customer_notes TEXT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_orders_rest (restaurant_id),
  INDEX idx_orders_table (table_id),
  INDEX idx_orders_session (session_id),
  UNIQUE KEY ux_orders_uid (order_uid),
  CONSTRAINT fk_orders_rest FOREIGN KEY (restaurant_id) REFERENCES restaurants(id) ON DELETE CASCADE,
  CONSTRAINT fk_orders_table FOREIGN KEY (table_id) REFERENCES tables(id) ON DELETE CASCADE,
  CONSTRAINT fk_orders_session FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE order_items (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  order_id BIGINT UNSIGNED NOT NULL,
  item_id BIGINT UNSIGNED NOT NULL,
  quantity INT UNSIGNED NOT NULL DEFAULT 1,
  price DECIMAL(12,2) NOT NULL,      -- price at time of order
  final_price DECIMAL(12,2) NOT NULL, -- price*quantity - per-item discount if any
  extras JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_order_items_order (order_id),
  CONSTRAINT fk_order_items_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
  CONSTRAINT fk_order_items_item FOREIGN KEY (item_id) REFERENCES menu_items(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------
-- Discounts
-- ---------------------------
CREATE TABLE discounts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  restaurant_id BIGINT UNSIGNED NOT NULL,
  type ENUM('global','dish','occasion','custom') NOT NULL DEFAULT 'global',
  value DECIMAL(10,2) NOT NULL,   -- if percent, convention in metadata
  is_percent TINYINT(1) DEFAULT 0,
  item_id BIGINT UNSIGNED NULL,    -- for dish-specific discounts
  start_date DATETIME NULL,
  end_date DATETIME NULL,
  metadata JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_discounts_rest (restaurant_id),
  CONSTRAINT fk_discounts_rest FOREIGN KEY (restaurant_id) REFERENCES restaurants(id) ON DELETE CASCADE,
  CONSTRAINT fk_discounts_item FOREIGN KEY (item_id) REFERENCES menu_items(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------
-- Payments (online & offline)
-- ---------------------------
CREATE TABLE payments (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  order_id BIGINT UNSIGNED NOT NULL,
  provider VARCHAR(128) NULL,             -- 'razorpay','stripe',NULL for offline
  provider_order_id VARCHAR(255) NULL,
  amount DECIMAL(12,2) NOT NULL,
  payment_mode ENUM('online','cash','card','manual_upi') NOT NULL DEFAULT 'online',
  status ENUM('success','failed','pending') NOT NULL DEFAULT 'success',
  confirmed_by BIGINT UNSIGNED NULL,      -- staff user id if offline
  confirmed_at DATETIME NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_payments_order (order_id),
  CONSTRAINT fk_payments_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------
-- Users, RBAC (roles & permissions), API Keys
-- ---------------------------
CREATE TABLE users (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  restaurant_id BIGINT UNSIGNED NULL,
  name VARCHAR(255) NULL,
  email VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  phone VARCHAR(50) NULL,
  is_active TINYINT(1) DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY ux_users_email (email),
  INDEX idx_users_rest (restaurant_id),
  CONSTRAINT fk_users_rest FOREIGN KEY (restaurant_id) REFERENCES restaurants(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE roles (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(64) NOT NULL UNIQUE, -- 'owner','manager','staff','admin'
  description VARCHAR(255) NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE permissions (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(128) NOT NULL UNIQUE,
  description VARCHAR(255) NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE role_permission (
  role_id INT UNSIGNED NOT NULL,
  permission_id INT UNSIGNED NOT NULL,
  PRIMARY KEY (role_id, permission_id),
  CONSTRAINT fk_rp_role FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE,
  CONSTRAINT fk_rp_perm FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE user_role (
  user_id BIGINT UNSIGNED NOT NULL,
  role_id INT UNSIGNED NOT NULL,
  PRIMARY KEY (user_id, role_id),
  CONSTRAINT fk_ur_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_ur_role FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- API keys for external integrations or restaurant-specific keys (limited scope)
CREATE TABLE api_keys (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  restaurant_id BIGINT UNSIGNED NULL,
  key_hash VARCHAR(255) NOT NULL,
  label VARCHAR(255) NULL,
  permissions JSON NULL,
  is_active TINYINT(1) DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at DATETIME NULL,
  INDEX idx_api_keys_rest (restaurant_id),
  CONSTRAINT fk_api_keys_rest FOREIGN KEY (restaurant_id) REFERENCES restaurants(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------
-- Audit, Analytics, Logs
-- ---------------------------
CREATE TABLE audit_logs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NULL,
  restaurant_id BIGINT UNSIGNED NULL,
  action VARCHAR(255) NOT NULL,
  entity VARCHAR(255) NULL,
  entity_id VARCHAR(128) NULL,
  details JSON NULL,
  ip_address VARCHAR(45) NULL,
  user_agent VARCHAR(512) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_audit_user (user_id),
  INDEX idx_audit_rest (restaurant_id),
  CONSTRAINT fk_audit_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_audit_rest FOREIGN KEY (restaurant_id) REFERENCES restaurants(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE analytics_events (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  restaurant_id BIGINT UNSIGNED NOT NULL,
  event_type VARCHAR(128) NOT NULL,
  payload JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_analytics_rest (restaurant_id),
  CONSTRAINT fk_analytics_rest FOREIGN KEY (restaurant_id) REFERENCES restaurants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------
-- Misc: Notification tokens, rate-limits, failed attempts
-- ---------------------------
CREATE TABLE notification_tokens (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NULL,
  restaurant_id BIGINT UNSIGNED NULL,
  token VARCHAR(1024),
  provider VARCHAR(64) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_notif_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_notif_rest FOREIGN KEY (restaurant_id) REFERENCES restaurants(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE failed_verifications (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  table_id BIGINT UNSIGNED NULL,
  ip_address VARCHAR(45) NULL,
  user_agent VARCHAR(512) NULL,
  attempts INT UNSIGNED DEFAULT 1,
  last_attempt_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_failed_ver_table (table_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------
-- Index tuning helper (example)
-- ---------------------------
CREATE INDEX idx_orders_rest_status ON orders (restaurant_id, status);
CREATE INDEX idx_orders_payment_status ON orders (payment_status);

-- ---------------------------
-- Triggers (example) -> create audit log on important changes
-- NOTE: Triggers require proper privileges. Use sparingly in high-throughput systems.
-- ---------------------------
DELIMITER $$

-- Trigger: on orders insert -> audit_logs
CREATE TRIGGER trg_orders_insert AFTER INSERT ON orders
FOR EACH ROW
BEGIN
  INSERT INTO audit_logs (user_id, restaurant_id, action, entity, entity_id, details, created_at)
  VALUES (NULL, NEW.restaurant_id, 'order_created', 'orders', NEW.id, JSON_OBJECT('order_uid', NEW.order_uid, 'total', NEW.total), NOW());
END$$

-- Trigger: on payments insert -> audit_logs
CREATE TRIGGER trg_payments_insert AFTER INSERT ON payments
FOR EACH ROW
BEGIN
  INSERT INTO audit_logs (user_id, restaurant_id, action, entity, entity_id, details, created_at)
  VALUES (NEW.confirmed_by, (SELECT restaurant_id FROM orders WHERE id = NEW.order_id), 'payment_recorded', 'payments', NEW.id, JSON_OBJECT('amount', NEW.amount, 'mode', NEW.payment_mode), NOW());
END$$

-- Trigger: on payments update -> audit_logs (status change)
CREATE TRIGGER trg_payments_update AFTER UPDATE ON payments
FOR EACH ROW
BEGIN
  IF NEW.status <> OLD.status THEN
    INSERT INTO audit_logs (user_id, restaurant_id, action, entity, entity_id, details, created_at)
    VALUES (NEW.confirmed_by, (SELECT restaurant_id FROM orders WHERE id = NEW.order_id), 'payment_status_changed', 'payments', NEW.id, JSON_OBJECT('old', OLD.status, 'new', NEW.status), NOW());
  END IF;
END$$

DELIMITER ;

-- ---------------------------
-- Sample seed for core roles
-- ---------------------------
INSERT INTO roles (name, description) VALUES ('owner','Restaurant Owner'), ('manager','Manager'), ('staff','Staff'), ('admin','Platform Admin');

-- ---------------------------
-- DB USER & PRIVILEGES (recommended approach)
-- Run as root/admin on DB server — adapt host & password.
-- ---------------------------
/*
CREATE USER 'tablyy_app'@'%' IDENTIFIED BY 'strong_password_here';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER ON tablyy.* TO 'tablyy_app'@'%';

CREATE USER 'tablyy_readonly'@'%' IDENTIFIED BY 'readonly_password';
GRANT SELECT ON tablyy.* TO 'tablyy_readonly'@'%';
FLUSH PRIVILEGES;
*/

-- End of schema
