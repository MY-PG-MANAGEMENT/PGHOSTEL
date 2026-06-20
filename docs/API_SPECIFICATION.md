# PG Manager - Backend API Specification
## Complete Endpoint Documentation for Mobile Screens

**Document Version:** 1.0  
**Scope:** Owner App + Super Admin App  
**Date:** June 19, 2026

---

## Table of Contents

1. [API Overview](#api-overview)
2. [Dashboard APIs](#dashboard-apis)
3. [Notification APIs](#notification-apis)
4. [Payment APIs](#payment-apis)
5. [Property APIs](#property-apis)
6. [Room & Bed APIs](#room--bed-apis)
7. [Tenant APIs](#tenant-apis)
8. [Settings APIs](#settings-apis)
9. [Admin APIs](#admin-apis)
10. [Common Response Formats](#common-response-formats)

---

## API Overview

### Base URL
```
http://localhost:8080/api
```

### Authentication
All endpoints require JWT token in header:
```
Authorization: Bearer {JWT_TOKEN}
```

### Response Format
All responses follow standard envelope:
```json
{
  "status": "SUCCESS|ERROR",
  "data": {},
  "message": "Human readable message",
  "timestamp": "2026-06-19T10:00:00Z"
}
```

### Standard Query Parameters
- `page`: Pagination page number (default: 0)
- `size`: Page size (default: 20)
- `sort`: Sort field and direction (e.g., `created_at,desc`)
- `search`: Search query for text fields
- `filters`: JSON object for advanced filters

---

## DASHBOARD APIs

### 1. Owner Dashboard Summary

**Screen:** Dashboard Module - Main Dashboard

#### Endpoint: GET /api/dashboard/owner-summary

**Purpose:** Get main KPIs for owner dashboard

**Query Parameters:**
- `propertyId` (optional): Filter by specific property
- `includeCharts` (boolean, default: true): Include chart data

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "totalTenants": 125,
    "occupiedBeds": 98,
    "vacantBeds": 27,
    "todayCollection": 24500,
    "monthlyRevenue": 1250000,
    "monthlyRevenueGrowth": 18.6,
    "pendingPayments": 24500,
    "pendingTenantsCount": 5,
    "complaintsOpen": 3,
    "complaintsResolved": 12,
    "revenueChartData": [
      { "date": "2026-06-01", "amount": 1200000 },
      { "date": "2026-06-02", "amount": 1210000 }
    ]
  }
}
```

**Required Tables:**
- `facility`, `facility_party`, `invoice`, `payment`, `admission`

**DB View:** `facility_occupancy_summary`, `pending_payment_summary`

---

#### Endpoint: GET /api/dashboard/revenue-stats

**Purpose:** Get revenue statistics for dashboard

**Query Parameters:**
- `period`: `DAILY|WEEKLY|MONTHLY|YEARLY` (default: MONTHLY)
- `propertyId` (optional): Filter by property
- `months`: Number of periods to return (default: 12)

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "totalRevenue": 1250000,
    "collectedAmount": 1200000,
    "pendingAmount": 50000,
    "collectionRate": 96.0,
    "averageRent": 10000,
    "revenueByProperty": [
      {
        "propertyName": "Royal PG House",
        "revenue": 600000,
        "collected": 580000,
        "pending": 20000
      }
    ],
    "monthlyTrend": [
      { "month": "2026-05", "revenue": 1200000, "collected": 1150000 },
      { "month": "2026-06", "revenue": 1250000, "collected": 1200000 }
    ]
  }
}
```

---

#### Endpoint: GET /api/dashboard/occupancy-stats

**Purpose:** Get occupancy statistics

**Query Parameters:**
- `propertyId` (optional): Filter by property

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "totalCapacity": 150,
    "occupied": 98,
    "vacant": 52,
    "occupancyPercent": 65.3,
    "byProperty": [
      {
        "propertyName": "Royal PG House",
        "totalCapacity": 60,
        "occupied": 48,
        "vacant": 12,
        "occupancyPercent": 80
      }
    ],
    "trend": [
      { "date": "2026-06-01", "occupancyPercent": 63.5 },
      { "date": "2026-06-02", "occupancyPercent": 65.3 }
    ]
  }
}
```

---

#### Endpoint: GET /api/dashboard/pending-payments

**Purpose:** Get list of pending payments

**Query Parameters:**
- `propertyId` (optional)
- `status`: `PENDING|OVERDUE|DUE_TODAY` (optional)
- `page`, `size` (pagination)

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "content": [
      {
        "invoiceId": 101,
        "invoiceNumber": "INV-001-202406",
        "tenantName": "Amit Sharma",
        "room": "Room 101",
        "amount": 10000,
        "pendingAmount": 5000,
        "dueDate": "2026-06-10",
        "daysOverdue": 9,
        "status": "OVERDUE"
      }
    ],
    "totalElements": 15,
    "totalPages": 1
  }
}
```

---

### 2. Analytics Dashboard

**Screen:** Dashboard Module - Analytics Dashboard

#### Endpoint: GET /api/analytics/metrics

**Purpose:** Get all analytics metrics

**Query Parameters:**
- `period`: Time period for analysis
- `propertyId` (optional)

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "occupancyRate": 65.3,
    "collectionRate": 96.0,
    "averageRentPerBed": 10000,
    "totalRevenue": 1250000,
    "revenueGrowth": 4.2,
    "topPropertiesByRevenue": [
      {
        "propertyName": "Royal PG House",
        "revenue": 600000,
        "occupancyPercent": 80,
        "tenantCount": 48
      }
    ],
    "recentActivity": [
      {
        "timestamp": "2026-06-19T10:30:00Z",
        "description": "Rent collected from Amit Sharma (Room 101)",
        "amount": 10000
      }
    ]
  }
}
```

---

#### Endpoint: GET /api/analytics/occupancy-breakdown

**Purpose:** Get occupancy breakdown by room type

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "totalBeds": 150,
    "occupiedBeds": 98,
    "vacantBeds": 52,
    "breakdown": [
      {
        "type": "Single Occupancy",
        "total": 50,
        "occupied": 40,
        "vacant": 10,
        "occupancyPercent": 80
      },
      {
        "type": "Double Occupancy",
        "total": 50,
        "occupied": 35,
        "vacant": 15,
        "occupancyPercent": 70
      },
      {
        "type": "Triple Sharing",
        "total": 50,
        "occupied": 23,
        "vacant": 27,
        "occupancyPercent": 46
      }
    ],
    "pieChartData": [
      { "label": "Occupied (98)", "value": 98, "color": "#6366F1" },
      { "label": "Vacant (52)", "value": 52, "color": "#E5E7EB" }
    ]
  }
}
```

---

## NOTIFICATION APIs

### 1. Get Notifications List

**Screen:** Notifications Module - Notifications List

#### Endpoint: GET /api/notifications

**Query Parameters:**
- `filter`: `ALL|UNREAD|IMPORTANT` (default: ALL)
- `category` (optional): Filter by category
- `page`, `size`: Pagination

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "content": [
      {
        "notificationId": 101,
        "category": "RENT_REMINDER",
        "categoryName": "Rent Reminder",
        "title": "Rent Payment Due",
        "message": "May rent for Room 101 is due on 10 May 2024.",
        "priority": "HIGH",
        "read": false,
        "important": true,
        "archived": false,
        "createdAt": "2026-06-19T10:00:00Z",
        "expiresAt": null
      }
    ],
    "unreadCount": 8,
    "importantCount": 5,
    "totalElements": 25
  }
}
```

---

### 2. Get Notification Details

**Screen:** Notifications Module - Notification Details

#### Endpoint: GET /api/notifications/{notificationId}

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "notificationId": 101,
    "category": "RENT_REMINDER",
    "categoryName": "Rent Reminder",
    "title": "May Rent Due",
    "message": "May rent for Room 101 (Bed 1 - Amit Sharma) is due on 10 May 2024. Please ensure payment is made on time to avoid late fees.",
    "priority": "HIGH",
    "entityType": "INVOICE",
    "entityId": 12345,
    "entityDetails": {
      "invoiceNumber": "INV-001-202405",
      "amount": 10000,
      "dueDate": "2026-06-10"
    },
    "read": false,
    "important": true,
    "archived": false,
    "createdAt": "2026-06-19T10:00:00Z"
  }
}
```

---

### 3. Mark Notification as Read

#### Endpoint: POST /api/notifications/{notificationId}/mark-read

**Response:** Standard success response

---

### 4. Archive Notification

#### Endpoint: POST /api/notifications/{notificationId}/archive

**Response:** Standard success response

---

### 5. Get Notification Preferences

**Screen:** Notifications Module - Notification Settings

#### Endpoint: GET /api/notifications/preferences

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "enableNotifications": true,
    "preferences": [
      {
        "categoryId": "RENT_REMINDER",
        "categoryName": "Rent Reminders",
        "enabled": true,
        "channels": [
          { "channelType": "IN_APP", "enabled": true },
          { "channelType": "EMAIL", "enabled": true },
          { "channelType": "SMS", "enabled": false },
          { "channelType": "PUSH", "enabled": true }
        ]
      },
      {
        "categoryId": "PAYMENT_UPDATE",
        "categoryName": "Payment Updates",
        "enabled": true,
        "channels": [
          { "channelType": "IN_APP", "enabled": true },
          { "channelType": "EMAIL", "enabled": false },
          { "channelType": "SMS", "enabled": true },
          { "channelType": "PUSH", "enabled": true }
        ]
      }
    ]
  }
}
```

---

### 6. Update Notification Preferences

#### Endpoint: PUT /api/notifications/preferences

**Request Body:**
```json
{
  "preferences": [
    {
      "categoryId": "RENT_REMINDER",
      "enabled": true,
      "channels": [
        { "channelType": "IN_APP", "enabled": true },
        { "channelType": "PUSH", "enabled": false }
      ]
    }
  ]
}
```

**Response:** Standard success response

---

## PAYMENT APIs

### 1. Payment Dashboard

**Screen:** Payment Management Module - Payment Dashboard

#### Endpoint: GET /api/payments/dashboard

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "totalCollection": 1125000,
    "thisMonth": 1250000,
    "pendingCollection": 24500,
    "noOfTenants": 98,
    "receivedToday": 82000,
    "noOfPaymentsToday": 3,
    "collectionOverview": {
      "collected": 1150000,
      "overdue": 12000,
      "pending": 20000,
      "collectionTrend": [
        { "date": "2026-06-15", "amount": 45000 },
        { "date": "2026-06-16", "amount": 52000 }
      ]
    },
    "quickActions": [
      { "action": "View Pending Dues", "icon": "alert", "count": 5 },
      { "action": "View Payment History", "icon": "history" },
      { "action": "Add Advance", "icon": "add" }
    ]
  }
}
```

---

### 2. Payment Details

**Screen:** Payment Management Module - Payment Details

#### Endpoint: GET /api/payments/{invoiceId}/details

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "invoiceId": 101,
    "invoiceNumber": "INV-001-202406",
    "tenantInfo": {
      "tenantId": 51,
      "name": "Amit Sharma",
      "room": "Room 101",
      "status": "Active"
    },
    "paymentDetails": {
      "invoiceMonth": "2026-06-01",
      "dueDate": "2026-06-10",
      "totalAmount": 10000,
      "amountDetails": [
        { "itemType": "Monthly Rent", "amount": 9000 },
        { "itemType": "Maintenance", "amount": 1000 }
      ],
      "advanceAdjustment": -500,
      "paidAmount": 0,
      "pendingAmount": 10000,
      "status": "PENDING"
    }
  }
}
```

---

### 3. Make Payment (Create Payment)

**Screen:** Payment Management Module - Make Payment

#### Endpoint: POST /api/payments

**Request Body:**
```json
{
  "invoiceId": 101,
  "amount": 10000,
  "paymentMethodType": "CASH",
  "paymentDate": "2026-06-19",
  "referenceNumber": "CHQ123456",
  "notes": "Payment received in cash"
}
```

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "paymentId": 501,
    "paymentNumber": "PAY-001-202406",
    "invoiceId": 101,
    "amount": 10000,
    "paymentMethodType": "CASH",
    "paymentDate": "2026-06-19",
    "status": "RECEIVED",
    "message": "Payment recorded successfully"
  }
}
```

---

### 4. Get Payment Methods

**Screen:** Payment Management Module - Payment Methods

#### Endpoint: GET /api/payments/methods

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "paymentMethods": [
      {
        "methodTypeId": "CASH",
        "name": "Cash Payment",
        "description": "Payment received in cash",
        "enabled": true,
        "icon": "money"
      },
      {
        "methodTypeId": "CHEQUE",
        "name": "Cheque",
        "description": "Payment via cheque",
        "enabled": true,
        "icon": "receipt"
      },
      {
        "methodTypeId": "UPI",
        "name": "UPI Transfer",
        "description": "Unified Payments Interface",
        "enabled": true,
        "icon": "phone"
      },
      {
        "methodTypeId": "NET_BANKING",
        "name": "Net Banking",
        "description": "Online bank transfer",
        "enabled": true,
        "icon": "bank"
      },
      {
        "methodTypeId": "WALLET",
        "name": "Digital Wallet",
        "description": "Payment via digital wallet",
        "enabled": true,
        "icon": "wallet"
      }
    ]
  }
}
```

---

### 5. Payment History

**Screen:** Payment Management Module - Payment History

#### Endpoint: GET /api/payments/history

**Query Parameters:**
- `tenantId` (optional)
- `propertyId` (optional)
- `month` (optional): Filter by month
- `status` (optional): `PAID|PARTIAL|PENDING|FAILED|REFUNDED`
- `page`, `size`: Pagination

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "content": [
      {
        "paymentId": 501,
        "paymentNumber": "PAY-001-202405",
        "invoiceNumber": "INV-001-202405",
        "tenantName": "Amit Sharma",
        "room": "Room 101",
        "month": "2026-05-01",
        "amount": 10000,
        "paymentMethodType": "CASH",
        "paymentDate": "2026-05-10",
        "status": "Paid"
      }
    ],
    "totalElements": 48,
    "totalPages": 3
  }
}
```

---

### 6. Pending Dues

**Screen:** Payment Management Module - Pending Dues

#### Endpoint: GET /api/payments/pending-dues

**Query Parameters:**
- `propertyId` (optional)
- `sortBy`: `AMOUNT|DUE_DATE|OVERDUE_DAYS` (default: OVERDUE_DAYS)
- `page`, `size`

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "content": [
      {
        "invoiceId": 102,
        "invoiceNumber": "INV-001-202406",
        "tenantName": "Rohit Kumar",
        "room": "Room 102",
        "propertyName": "Royal PG House",
        "amount": 10000,
        "pendingAmount": 10000,
        "dueDate": "2026-06-10",
        "daysOverdue": 9,
        "status": "OVERDUE",
        "collectionHistory": [
          { "month": "May 2026", "status": "Collected" }
        ]
      }
    ],
    "totalPendingAmount": 24500,
    "totalElements": 3
  }
}
```

---

### 7. Receipt Download/View

**Screen:** Payment Management Module - Receipt

#### Endpoint: GET /api/payments/{paymentId}/receipt

**Query Parameters:**
- `format`: `PDF|JSON` (default: PDF)

**Response (JSON format):**
```json
{
  "status": "SUCCESS",
  "data": {
    "receiptNumber": "RCP-001-202406",
    "organizationName": "PG Manager",
    "organizationAddress": "Bangalore, India",
    "receiptDate": "2026-06-19",
    "paymentDetails": {
      "invoiceNumber": "INV-001-202406",
      "tenantName": "Amit Sharma",
      "tenantPhone": "+91 98765 43210",
      "room": "Room 101, Royal PG House",
      "amount": 10000,
      "paymentMethod": "CASH",
      "referenceNumber": "CHQ123456",
      "notes": "Payment received in cash"
    },
    "generatedAt": "2026-06-19T15:30:00Z"
  }
}
```

---

### 8. Advance Payment

**Screen:** Payment Management Module - Advance Payment

#### Endpoint: POST /api/payments/advances

**Request Body:**
```json
{
  "tenantId": 51,
  "admissionId": 201,
  "amount": 5000,
  "paymentMethodType": "CASH",
  "paymentDate": "2026-06-19",
  "notes": "Advance payment for future months"
}
```

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "advanceId": 301,
    "amount": 5000,
    "balanceCreated": 5000,
    "applicableFrom": "2026-07-01",
    "message": "Advance payment recorded. Balance of ₹5,000 will be applied to future invoices."
  }
}
```

---

## PROPERTY APIs

### 1. List Properties

**Screen:** Property Management Module - Property List

#### Endpoint: GET /api/properties

**Query Parameters:**
- `search`: Search by property name
- `status`: `ACTIVE|INACTIVE|ARCHIVED`
- `page`, `size`

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "content": [
      {
        "propertyId": 10,
        "name": "Royal PG House",
        "location": "Koramangala, Bangalore",
        "postalCode": "560034",
        "totalRooms": 60,
        "occupiedBeds": 48,
        "vacantBeds": 12,
        "occupancyPercent": 80,
        "monthlyRevenue": 600000,
        "status": "ACTIVE",
        "thumbnail": "https://..."
      }
    ],
    "totalElements": 5,
    "totalPages": 1
  }
}
```

---

### 2. Create Property

**Screen:** Property Management Module - Add Property

#### Endpoint: POST /api/properties

**Request Body:**
```json
{
  "propertyName": "Green View PG",
  "address": "123 Main Street",
  "city": "Bangalore",
  "state": "Karnataka",
  "postalCode": "560001",
  "country": "India",
  "description": "Premium PG with modern amenities",
  "totalRooms": 20,
  "roomDetails": [
    {
      "roomNumber": "101",
      "floor": 1,
      "noOfBeds": 2,
      "sharingType": "DOUBLE",
      "monthlyRent": 10000,
      "size": 250,
      "description": "Room with attached bathroom"
    }
  ]
}
```

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "propertyId": 11,
    "message": "Property created successfully"
  }
}
```

---

### 3. Get Property Details

**Screen:** Property Management Module - Property Details

#### Endpoint: GET /api/properties/{propertyId}

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "propertyId": 10,
    "name": "Royal PG House",
    "location": "Koramangala, Bangalore - 560034",
    "description": "Premium PG with modern amenities in the heart of Koramangala",
    "totalRooms": 60,
    "totalBeds": 120,
    "occupiedBeds": 98,
    "vacantBeds": 22,
    "occupancyPercent": 81.67,
    "monthlyRevenue": 600000,
    "statistics": {
      "totalTenants": 98,
      "totalStaff": 8,
      "maintenanceComplaint": 0,
      "securityDeposit": 1200000,
      "monthlyExpense": 150000
    },
    "amenities": [
      { "amenityId": "WIFI", "name": "WiFi", "available": true },
      { "amenityId": "POWER_BACKUP", "name": "Power Backup", "available": true }
    ],
    "status": "ACTIVE",
    "createdAt": "2025-01-15"
  }
}
```

---

### 4. Update Property

**Screen:** Property Management Module - Edit Property

#### Endpoint: PUT /api/properties/{propertyId}

**Request Body:**
```json
{
  "propertyName": "Royal PG House (Updated)",
  "description": "Updated description",
  "amenitiesIds": ["WIFI", "POWER_BACKUP", "CCTV"]
}
```

**Response:** Standard success response

---

### 5. Get Floors

**Screen:** Property Management Module - Floors

#### Endpoint: GET /api/properties/{propertyId}/floors

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "floors": [
      {
        "floorId": 100,
        "floorNumber": "Ground Floor",
        "totalRooms": 20,
        "totalBeds": 40,
        "occupiedBeds": 30,
        "vacantBeds": 10,
        "occupancyPercent": 75,
        "rooms": [
          {
            "roomId": 101,
            "roomNumber": "101",
            "totalBeds": 3,
            "occupiedBeds": 3,
            "sharingType": "TRIPLE_SHARING",
            "monthlyRent": 9000
          }
        ]
      },
      {
        "floorId": 101,
        "floorNumber": "First Floor",
        "totalRooms": 20,
        "totalBeds": 40,
        "occupiedBeds": 35,
        "vacantBeds": 5,
        "occupancyPercent": 87.5
      }
    ]
  }
}
```

---

### 6. Get Amenities

**Screen:** Property Management Module - Amenities

#### Endpoint: GET /api/properties/{propertyId}/amenities

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "amenities": [
      {
        "amenityTypeId": "WIFI",
        "name": "WiFi",
        "icon": "wifi",
        "available": true,
        "details": "High-speed WiFi available 24/7"
      },
      {
        "amenityTypeId": "POWER_BACKUP",
        "name": "Power Backup",
        "icon": "bolt",
        "available": true,
        "details": "24-hour power backup with inverter"
      },
      {
        "amenityTypeId": "CCTV",
        "name": "CCTV",
        "icon": "videocam",
        "available": true,
        "details": "CCTV cameras in all common areas"
      },
      {
        "amenityTypeId": "AC",
        "name": "Air Conditioning",
        "icon": "ac_unit",
        "available": false,
        "details": null
      }
    ]
  }
}
```

---

### 7. Update Amenities

#### Endpoint: PUT /api/properties/{propertyId}/amenities

**Request Body:**
```json
{
  "amenities": [
    { "amenityTypeId": "WIFI", "available": true },
    { "amenityTypeId": "AC", "available": true, "details": "AC in all rooms" }
  ]
}
```

**Response:** Standard success response

---

## ROOM & BED APIs

### 1. List Rooms

**Screen:** Room Management Module - Room List

#### Endpoint: GET /api/rooms

**Query Parameters:**
- `propertyId`: Required
- `floorId` (optional)
- `status`: `ACTIVE|MAINTENANCE|CLOSED` (optional)
- `occupancyFilter`: `ALL|OCCUPIED|VACANT` (optional)
- `page`, `size`

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "content": [
      {
        "roomId": 101,
        "roomNumber": "101",
        "floor": "Ground Floor",
        "totalBeds": 3,
        "occupiedBeds": 3,
        "vacantBeds": 0,
        "sharingType": "TRIPLE_SHARING",
        "occupancyPercent": 100,
        "monthlyRent": 9000,
        "totalSize": 220,
        "status": "ACTIVE",
        "occupants": [
          { "bedNumber": "1", "tenantName": "Amit Sharma", "status": "Occupied" }
        ]
      }
    ],
    "totalElements": 60,
    "totalPages": 3
  }
}
```

---

### 2. Get Room Details

**Screen:** Room Management Module - Room Details

#### Endpoint: GET /api/rooms/{roomId}

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "roomId": 101,
    "roomNumber": "101",
    "floor": "Ground Floor",
    "propertyName": "Royal PG House",
    "totalBeds": 3,
    "totalSize": 220,
    "monthlyRent": 9000,
    "sharingType": "TRIPLE_SHARING",
    "description": "Spacious triple sharing room with attached bathroom",
    "occupancyPercent": 100,
    "status": "ACTIVE",
    "beds": [
      {
        "bedId": 1001,
        "bedNumber": "1",
        "status": "OCCUPIED",
        "monthlyRent": 3000,
        "deposit": 3000,
        "occupant": {
          "tenantId": 51,
          "name": "Amit Sharma",
          "phone": "+91 98765 43210",
          "moveInDate": "2026-05-01"
        }
      }
    ],
    "amenities": [
      { "name": "Attached Bathroom", "status": "Available" },
      { "name": "AC", "status": "Available" },
      { "name": "WiFi", "status": "Available" }
    ],
    "photos": [
      { "photoId": 1, "url": "https://...", "description": "Room overview" }
    ]
  }
}
```

---

### 3. Get Bed Details

**Screen:** Room Management Module - Bed Details

#### Endpoint: GET /api/beds/{bedId}

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "bedId": 1001,
    "bedNumber": "Bed 1",
    "roomNumber": "Room 101",
    "propertyName": "Royal PG House",
    "totalBeds": 3,
    "sharingType": "TRIPLE_SHARING",
    "status": "OCCUPIED",
    "monthlyRent": 3000,
    "securityDeposit": 3000,
    "occupant": {
      "occupantId": 51,
      "name": "Amit Sharma",
      "phone": "+91 98765 43210",
      "email": "amit.sharma@email.com",
      "moveInDate": "2026-05-01",
      "moveInMonthsAgo": 1,
      "status": "ACTIVE",
      "profilePhoto": "https://..."
    },
    "moveOutDate": null,
    "advanceBalance": 0
  }
}
```

---

### 4. Assign Tenant to Bed

**Screen:** Room Management Module - Assign Tenant

#### Endpoint: PUT /api/beds/{bedId}/tenant

**Request Body:**
```json
{
  "tenantId": 52,
  "moveInDate": "2026-06-20",
  "monthlyRent": 3000,
  "securityDeposit": 3000,
  "advanceAmount": 0
}
```

**Response:** Standard success response

---

### 5. Get Room Photos

**Screen:** Room Management Module - Room Photos

#### Endpoint: GET /api/rooms/{roomId}/photos

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "photos": [
      {
        "photoId": 1,
        "url": "https://cdn.example.com/room101_1.jpg",
        "displayOrder": 1,
        "description": "Room overview",
        "uploadedAt": "2026-01-15"
      },
      {
        "photoId": 2,
        "url": "https://cdn.example.com/room101_2.jpg",
        "displayOrder": 2,
        "description": "Bathroom",
        "uploadedAt": "2026-01-15"
      }
    ]
  }
}
```

---

### 6. Upload Room Photos

#### Endpoint: POST /api/rooms/{roomId}/photos

**Request:** Multipart form data
- `file`: Image file (PNG/JPG, max 5MB)
- `description` (optional): Photo description
- `displayOrder` (optional): Order index

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "photoId": 3,
    "url": "https://cdn.example.com/room101_3.jpg",
    "message": "Photo uploaded successfully"
  }
}
```

---

## TENANT APIs

### 1. List Tenants

**Screen:** Tenant Management Module - Tenant List

#### Endpoint: GET /api/tenants

**Query Parameters:**
- `propertyId` (optional)
- `status`: `ACTIVE|INACTIVE|CHECKOUT_PENDING|CHECKOUT_COMPLETED`
- `search`: Search by name or mobile
- `page`, `size`

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "content": [
      {
        "tenantId": 51,
        "name": "Amit Sharma",
        "phone": "+91 98765 43210",
        "room": "Room 101, Bed 1",
        "moveInDate": "2026-05-01",
        "monthlyRent": 9000,
        "status": "ACTIVE",
        "pendingRent": 0,
        "profilePhoto": "https://..."
      }
    ],
    "totalElements": 98,
    "totalPages": 5
  }
}
```

---

### 2. Get Tenant Profile

**Screen:** Tenant Management Module - Tenant Profile

#### Endpoint: GET /api/tenants/{tenantId}

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "tenantId": 51,
    "personalDetails": {
      "name": "Amit Sharma",
      "phone": "+91 98765 43210",
      "email": "amit.sharma@email.com",
      "gender": "Male",
      "dateOfBirth": "1995-03-15",
      "aadhaarNumber": "123456789012",
      "address": "123 Main Street, Delhi"
    },
    "admissionDetails": {
      "moveInDate": "2026-05-01",
      "monthlyRent": 9000,
      "securityDeposit": 9000,
      "room": "Room 101, Bed 1",
      "status": "ACTIVE",
      "noticeperiod": "30 days"
    },
    "documents": [
      { "documentType": "Aadhaar Card", "verified": true, "verifiedDate": "2026-05-01" }
    ],
    "emergencyContacts": [
      { "name": "John Sharma", "relation": "Brother", "phone": "+91 98765 43211" }
    ],
    "employment": {
      "companyName": "Tech Corp",
      "designation": "Software Engineer",
      "salary": 50000,
      "email": "amit@techcorp.com"
    },
    "billingInfo": {
      "totalPaid": 9000,
      "totalPending": 0,
      "advanceBalance": 0,
      "nextDueDate": "2026-07-01"
    }
  }
}
```

---

### 3. Update Tenant Personal Details

**Screen:** Tenant Management Module - Personal Details

#### Endpoint: PUT /api/tenants/{tenantId}/personal-details

**Request Body:**
```json
{
  "email": "amit.sharma.new@email.com",
  "phone": "+91 98765 43210",
  "address": "123 New Street, Delhi"
}
```

**Response:** Standard success response

---

### 4. Upload Identity Document

**Screen:** Tenant Management Module - ID Documents

#### Endpoint: POST /api/tenants/{tenantId}/documents

**Request:** Multipart form data
- `documentType`: AADHAAR|PAN|PASSPORT|DRIVING_LICENSE
- `file`: Document image
- `documentNumber` (optional)

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "documentId": 1001,
    "documentType": "AADHAAR",
    "verificationStatus": "PENDING",
    "message": "Document uploaded for verification"
  }
}
```

---

### 5. Get Emergency Contacts

**Screen:** Tenant Management Module - Emergency Contact

#### Endpoint: GET /api/tenants/{tenantId}/emergency-contacts

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "emergencyContacts": [
      {
        "contactId": 101,
        "name": "John Sharma",
        "relationshipType": "Brother",
        "phone": "+91 98765 43211",
        "alternatPhone": "+91 87654 32109",
        "address": "123 Main Street, Delhi",
        "isPrimary": true
      }
    ]
  }
}
```

---

### 6. Add/Update Emergency Contact

#### Endpoint: POST /api/tenants/{tenantId}/emergency-contacts

**Request Body:**
```json
{
  "name": "Jane Sharma",
  "relationshipType": "Sister",
  "phone": "+91 98765 43212",
  "alternatePhone": "+91 87654 32110",
  "address": "456 Park Avenue, Mumbai",
  "isPrimary": false
}
```

**Response:** Standard success response

---

### 7. Get Employment Details

**Screen:** Tenant Management Module - Job Information

#### Endpoint: GET /api/tenants/{tenantId}/employment

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "companyName": "Tech Corp",
    "designation": "Software Engineer",
    "employeeId": "TC123456",
    "monthlySalary": 50000,
    "workEmail": "amit@techcorp.com",
    "officeAddress": "Tech Park, Bangalore"
  }
}
```

---

### 8. Update Employment Details

#### Endpoint: PUT /api/tenants/{tenantId}/employment

**Request Body:**
```json
{
  "companyName": "Tech Corp",
  "designation": "Senior Engineer",
  "employeeId": "TC123456",
  "monthlySalary": 60000,
  "workEmail": "amit@techcorp.com",
  "officeAddress": "Tech Park, Bangalore"
}
```

**Response:** Standard success response

---

### 9. Create New Admission

**Screen:** Tenant Management Module - New Admission

#### Endpoint: POST /api/admissions

**Request Body:**
```json
{
  "tenantId": 51,
  "bedId": 1001,
  "moveInDate": "2026-06-20",
  "monthlyRent": 9000,
  "securityDeposit": 9000,
  "advanceAmount": 0,
  "noticePeriod": 30
}
```

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "admissionId": 201,
    "message": "Admission created successfully"
  }
}
```

---

### 10. Get Admission Agreement

**Screen:** Tenant Management Module - Agreement

#### Endpoint: GET /api/admissions/{admissionId}/agreement

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "agreementId": 301,
    "agreementNumber": "AGR-001-202406",
    "agreementType": "ACCOMMODATION",
    "fromDate": "2026-06-20",
    "thruDate": "2027-06-19",
    "status": "DRAFT",
    "terms": "... full agreement text ...",
    "tenantName": "Amit Sharma",
    "monthlyRent": 9000,
    "securityDeposit": 9000,
    "noticeperiod": "30 days"
  }
}
```

---

### 11. Sign Agreement

#### Endpoint: POST /api/admissions/{admissionId}/agreement/sign

**Request Body:**
```json
{
  "signedAt": "2026-06-20T10:30:00Z"
}
```

**Response:** Standard success response

---

### 12. Checkout Process

**Screen:** Tenant Management Module - Checkout

#### Endpoint: POST /api/admissions/{admissionId}/checkout

**Request Body:**
```json
{
  "checkoutDate": "2026-06-20",
  "pendingDues": 0,
  "damageCharges": 0,
  "otherDeductions": 500
}
```

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "checkoutId": 401,
    "totalDeductions": 500,
    "refundableDeposit": 8500,
    "status": "PENDING_SETTLEMENT"
  }
}
```

---

### 13. Deposit Settlement

**Screen:** Tenant Management Module - Deposit Settlement

#### Endpoint: POST /api/admissions/{admissionId}/checkout/settle

**Request Body:**
```json
{
  "refundMethod": "BANK_TRANSFER",
  "refundAmount": 8500,
  "settledAt": "2026-06-22"
}
```

**Response:** Standard success response

---

## SETTINGS APIs

### 1. Get User Profile

**Screen:** Settings Module - Profile Information

#### Endpoint: GET /api/settings/profile

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "firstName": "Rajesh",
    "lastName": "Kumar",
    "email": "rajesh@pgmanager.com",
    "phone": "+91 98765 43210",
    "dateOfBirth": "1988-05-12",
    "gender": "Male",
    "address": "123 Property Lane, Bangalore",
    "profilePhoto": "https://..."
  }
}
```

---

### 2. Update User Profile

#### Endpoint: PUT /api/settings/profile

**Request Body:**
```json
{
  "firstName": "Rajesh",
  "lastName": "Kumar",
  "email": "rajesh.new@pgmanager.com",
  "phone": "+91 98765 43211",
  "address": "123 New Property Lane, Bangalore"
}
```

**Response:** Standard success response

---

### 3. Change Password

**Screen:** Settings Module - Change Password

#### Endpoint: PUT /api/settings/change-password

**Request Body:**
```json
{
  "currentPassword": "currentPass123",
  "newPassword": "newPass123",
  "confirmPassword": "newPass123"
}
```

**Response:** Standard success response

---

### 4. Get User Preferences

**Screen:** Settings Module - App & Preferences

#### Endpoint: GET /api/settings/preferences

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "theme": "LIGHT",
    "accentColor": "#6366F1",
    "fontSize": "MEDIUM",
    "language": "en",
    "dateFormat": "dd/MM/yyyy",
    "timeFormat": "12h",
    "currency": "INR",
    "timezone": "Asia/Kolkata"
  }
}
```

---

### 5. Update User Preferences

#### Endpoint: PUT /api/settings/preferences

**Request Body:**
```json
{
  "theme": "DARK",
  "fontSize": "LARGE",
  "language": "hi",
  "dateFormat": "dd-MM-yyyy"
}
```

**Response:** Standard success response

---

## ADMIN APIs

### 1. Admin Dashboard

**Screen:** Super Admin Module - Dashboard

#### Endpoint: GET /api/admin/dashboard

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "platformStats": {
      "totalProperties": 128,
      "totalTenants": 2450,
      "monthlyRevenue": 156800000,
      "totalRevenue": 2450000000,
      "activeSubscriptions": 128
    },
    "revenueStats": {
      "thisMonth": 156800000,
      "lastMonth": 150500000,
      "growth": 4.2,
      "trend": [
        { "month": "2026-05", "revenue": 150500000 },
        { "month": "2026-06", "revenue": 156800000 }
      ]
    },
    "topCustomers": [
      { "organizationName": "Royal Properties", "revenue": 15000000, "properties": 5 }
    ],
    "paymentStatus": {
      "paid": 2400,
      "pending": 50,
      "overdue": 15,
      "refunded": 5
    }
  }
}
```

---

### 2. Manage Properties

**Screen:** Super Admin Module - Properties

#### Endpoint: GET /api/admin/properties

**Query Parameters:**
- `search`, `status`, `page`, `size`

**Response:** Similar to owner property list but with admin controls

---

### 3. Manage Users

**Screen:** Super Admin Module - Users

#### Endpoint: GET /api/admin/users

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "content": [
      {
        "userId": 1,
        "name": "Rajesh Kumar",
        "email": "rajesh@pgmanager.com",
        "role": "OWNER",
        "organization": "Royal Properties",
        "status": "ACTIVE",
        "lastLogin": "2026-06-19T10:00:00Z"
      }
    ]
  }
}
```

---

### 4. Manage Roles & Permissions

**Screen:** Super Admin Module - Roles & Permissions

#### Endpoint: GET /api/admin/roles

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "roles": [
      {
        "roleId": "OWNER",
        "name": "Owner",
        "permissions": [
          "DASHBOARD_VIEW",
          "PROPERTY_MANAGE",
          "TENANT_MANAGE",
          "BILLING_MANAGE",
          "REPORT_VIEW",
          "SETTINGS_MANAGE"
        ]
      },
      {
        "roleId": "PROPERTY_MANAGER",
        "name": "Property Manager",
        "permissions": [
          "PROPERTY_MANAGE",
          "TENANT_MANAGE",
          "REPORT_VIEW"
        ]
      }
    ]
  }
}
```

---

### 5. Manage Plans & Pricing

**Screen:** Super Admin Module - Plans & Pricing

#### Endpoint: GET /api/admin/plans

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "plans": [
      {
        "planId": 1,
        "planCode": "BASIC",
        "name": "Basic Plan",
        "priceMonthly": 999,
        "propertyLimit": 10,
        "status": "ACTIVE",
        "features": [
          { "feature": "DASHBOARD_VIEW", "enabled": true },
          { "feature": "PROPERTY_MANAGE", "enabled": true }
        ]
      }
    ]
  }
}
```

---

### 6. List Customers

**Screen:** Super Admin Module - Customers

#### Endpoint: GET /api/admin/customers

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "content": [
      {
        "organizationId": 1,
        "organizationName": "Royal Properties",
        "ownerName": "Rajesh Kumar",
        "email": "rajesh@pgmanager.com",
        "phone": "+91 98765 43210",
        "propertiesCount": 5,
        "tenantsCount": 450,
        "monthlyRevenue": 15000000,
        "subscriptionPlan": "Premium Plan",
        "status": "ACTIVE",
        "joinedDate": "2025-01-15"
      }
    ]
  }
}
```

---

### 7. View Audit Logs

**Screen:** Super Admin Module - Audit Logs

#### Endpoint: GET /api/admin/audit-logs

**Query Parameters:**
- `actionType`, `entityType`, `userId`, `page`, `size`

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "content": [
      {
        "auditLogId": 1001,
        "timestamp": "2026-06-19T10:30:00Z",
        "userId": 1,
        "userName": "Rajesh Kumar",
        "action": "CREATE",
        "entityType": "TENANT",
        "entityId": 51,
        "details": "New tenant Amit Sharma admitted in Room 101",
        "changes": {
          "oldValues": null,
          "newValues": { "name": "Amit Sharma", "room": "101" }
        }
      }
    ]
  }
}
```

---

### 8. System Settings

**Screen:** Super Admin Module - System Settings

#### Endpoint: GET /api/admin/settings

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "settings": [
      {
        "settingKey": "PLATFORM_NAME",
        "settingValue": "PG Manager SaaS",
        "description": "Platform name"
      },
      {
        "settingKey": "TAX_RATE",
        "settingValue": "18",
        "description": "Default tax rate percentage"
      },
      {
        "settingKey": "MAX_PROPERTIES_FREE_TIER",
        "settingValue": "10",
        "description": "Maximum properties in free tier"
      }
    ]
  }
}
```

---

## COMMON RESPONSE FORMATS

### Success Response Template

```json
{
  "status": "SUCCESS",
  "data": { /* varies by endpoint */ },
  "message": "Operation completed successfully",
  "timestamp": "2026-06-19T10:30:00Z"
}
```

### Error Response Template

```json
{
  "status": "ERROR",
  "data": null,
  "message": "Detailed error message",
  "errors": [
    {
      "field": "email",
      "message": "Email already exists"
    }
  ],
  "timestamp": "2026-06-19T10:30:00Z"
}
```

### Paginated Response Template

```json
{
  "content": [ /* array of items */ ],
  "totalElements": 150,
  "totalPages": 8,
  "currentPage": 0,
  "pageSize": 20,
  "hasNext": true,
  "hasPrevious": false
}
```

---

## HTTP Status Codes

| Code | Usage |
|------|-------|
| 200 | Successful GET/PUT/DELETE |
| 201 | Successful POST (resource created) |
| 204 | Successful DELETE (no content) |
| 400 | Bad request (invalid input) |
| 401 | Unauthorized (missing/invalid token) |
| 403 | Forbidden (insufficient permissions) |
| 404 | Not found |
| 409 | Conflict (e.g., duplicate resource) |
| 500 | Server error |
| 503 | Service unavailable |

---

## Authentication

### Login

**Endpoint:** POST /api/auth/login

**Request:**
```json
{
  "username": "rajesh@pgmanager.com",
  "password": "password123"
}
```

**Response:**
```json
{
  "status": "SUCCESS",
  "data": {
    "accessToken": "eyJhbGciOiJIUzI1NiIs...",
    "refreshToken": "eyJhbGciOiJIUzI1NiIs...",
    "expiresIn": 3600,
    "user": {
      "userId": 1,
      "name": "Rajesh Kumar",
      "email": "rajesh@pgmanager.com",
      "role": "OWNER",
      "organization": "Royal Properties"
    }
  }
}
```

### Refresh Token

**Endpoint:** POST /api/auth/refresh

**Request:**
```json
{
  "refreshToken": "eyJhbGciOiJIUzI1NiIs..."
}
```

---

## Rate Limiting

API endpoints are rate-limited:
- **Standard**: 1000 requests per hour
- **Admin**: 5000 requests per hour

Rate limit headers:
- `X-RateLimit-Limit`: Total requests allowed
- `X-RateLimit-Remaining`: Remaining requests
- `X-RateLimit-Reset`: Unix timestamp when limit resets

---

**Document Version:** 1.0  
**Last Updated:** 2026-06-19  
**Next Review:** After backend implementation starts
