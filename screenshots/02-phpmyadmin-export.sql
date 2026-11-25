-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: localhost
-- Generation Time: Nov 25, 2026 at 12:06 PM
-- Server version: 10.4.32-MariaDB
-- PHP Version: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `ssb_inventory`
--

-- --------------------------------------------------------

--
-- Table structure for table `items`
--

CREATE TABLE `items` (
  `id` int(10) UNSIGNED NOT NULL,
  `sku` varchar(32) NOT NULL,
  `name` varchar(100) NOT NULL,
  `category` varchar(50) NOT NULL DEFAULT 'General',
  `quantity` int(10) UNSIGNED NOT NULL DEFAULT 0,
  `unit_price` decimal(10,2) NOT NULL DEFAULT 0.00,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `items`
--

INSERT INTO `items` (`id`, `sku`, `name`, `category`, `quantity`, `unit_price`, `created_at`, `updated_at`) VALUES
(1, 'LAP-001', 'Dell Latitude 5440 Laptop', 'Hardware', 12, 68500.00, '2026-11-25 06:33:50', '2026-11-25 06:33:50'),
(2, 'LAP-002', 'Lenovo ThinkPad E14', 'Hardware', 7, 61200.00, '2026-11-25 06:33:50', '2026-11-25 06:33:50'),
(3, 'MON-001', 'LG 24\" IPS Monitor', 'Hardware', 20, 11800.00, '2026-11-25 06:33:50', '2026-11-25 06:33:50'),
(4, 'KBD-001', 'Logitech K120 Keyboard', 'Accessories', 45, 650.00, '2026-11-25 06:33:50', '2026-11-25 06:33:50'),
(5, 'MSE-001', 'Logitech M90 Mouse', 'Accessories', 60, 399.00, '2026-11-25 06:33:50', '2026-11-25 06:33:50'),
(6, 'HDS-001', 'Jabra Evolve2 30 Headset', 'Accessories', 3, 5400.00, '2026-11-25 06:33:50', '2026-11-25 06:33:50'),
(7, 'NET-001', 'TP-Link 8-Port Gigabit Switch', 'Networking', 5, 1999.00, '2026-11-25 06:33:50', '2026-11-25 06:33:50'),
(8, 'NET-002', 'Cat6 Patch Cable 2m', 'Networking', 80, 149.00, '2026-11-25 06:33:50', '2026-11-25 06:33:50'),
(9, 'LIC-001', 'Office Suite Licence (1 year)', 'Software', 25, 6200.00, '2026-11-25 06:33:50', '2026-11-25 06:33:50'),
(10, 'UPS-001', 'APC 600VA UPS', 'Hardware', 2, 3450.00, '2026-11-25 06:33:50', '2026-11-25 06:33:50');

--
-- Indexes for dumped tables
--

--
-- Indexes for table `items`
--
ALTER TABLE `items`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_items_sku` (`sku`),
  ADD KEY `idx_items_category` (`category`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `items`
--
ALTER TABLE `items`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
