-- TESTE DE ROLLBACK: esta migration falha de propósito (será revertida logo em seguida).
SELECT * FROM table_that_does_not_exist;
