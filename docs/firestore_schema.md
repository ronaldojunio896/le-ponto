# Esquema Firebase

## users/{uid}

- `name`: nome do funcionário
- `email`: e-mail de login
- `role`: `employee` ou `admin`
- `active`: bloqueia/libera acesso
- `hourlyRate`: valor por hora
- `createdAt`: horário do servidor

## pinCredentials/{uid}

Coleção bloqueada pelas regras do Firestore. Usada apenas por Cloud Functions.

- `pinHash`: PIN com hash bcrypt
- `updatedAt`: horário do servidor

## stores/le-racoes-sao-gabriel

- `name`
- `address`
- `latitude`
- `longitude`
- `radiusMeters`
- `coordinateNeedsReview`
- `updatedAt`

## punches/{punchId}

- `employeeId`
- `employeeName`
- `type`: `entry`, `lunchOut`, `lunchIn`, `exit`
- `storeId`
- `latitude`
- `longitude`
- `accuracy`
- `storeLatitude`
- `storeLongitude`
- `distanceMeters`
- `radiusMeters`
- `outOfRadius`
- `justification`
- `serverTime`
- `edited`
- `editJustification`
- `editedBy`
- `editedAt`
- `createdAt`

## changeLogs/{logId}

- `entity`
- `entityId`
- `action`
- `before`
- `after`
- `justification`
- `adminId`
- `adminName`
- `createdAt`

## overtimeApprovals/{approvalId}

- `employeeId`
- `weekStart`
- `minutes`
- `justification`
- `approvedBy`
- `approvedByName`
- `createdAt`
