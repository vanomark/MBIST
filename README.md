# MBIST Controller

Параметризуемый **MBIST (Memory Built-In Self-Test) controller** для тестирования SRAM/памяти. Модуль выполняет последовательность операций чтения/записи, проверяет полученные данные и фиксирует обнаруженные ошибки.

## Возможности

* параметризуемые `DEPTH`, `DATA_W` и `ADDR_W`;
* интерфейс `CE / WE / ADDR / WDATA / RDATA`;
* обнаружение **SAF**, **TF** и **RDF**;
* определение адреса и битовой маски ошибки;
* сигнал завершения теста `done`.

## Алгоритм

Используется следующая March-подобная последовательность по адресам `0 → DEPTH-1`:

```text
↑ (w0, r0)
↑ (r0, w1, r1)
↑ (r1, w0, r0)
```

где:

* `w0` — запись нулей;
* `w1` — запись единиц;
* `r0` — чтение и проверка нулей;
* `r1` — чтение и проверка единиц.

### Fault coverage

| Fault                            | Описание                           |
| -------------------------------- | ---------------------------------- |
| **SAF (Stuck-At Fault)**         | Ячейка зафиксирована в `0` или `1` |
| **TF (Transition Fault)**        | Ошибка перехода `0→1` или `1→0`    |
| **RDF (Read Destructive Fault)** | Чтение изменяет состояние ячейки   |

Повторные чтения `r0` и `r1` позволяют обнаруживать проявления RDF, а чередование `w0/w1` — transition faults.

## Интерфейс

### Controller

| Signal           | I/O    |    Width | Description           |
| ---------------- | ------ | -------: | --------------------- |
| `clk`            | Input  |        1 | Clock                 |
| `rst`            | Input  |        1 | Synchronous reset     |
| `start`          | Input  |        1 | Start test            |
| `done`           | Output |        1 | Test completed        |
| `fail`           | Output |        1 | Error detected        |
| `fail_addr`      | Output | `ADDR_W` | Address of last error |
| `fail_data_mask` | Output | `DATA_W` | Error bit mask        |

### Memory

| Signal      | I/O    |    Width | Description    |
| ----------- | ------ | -------: | -------------- |
| `mem_ce`    | Output |        1 | Memory enable  |
| `mem_we`    | Output |        1 | Write enable   |
| `mem_addr`  | Output | `ADDR_W` | Memory address |
| `mem_wdata` | Output | `DATA_W` | Write data     |
| `mem_rdata` | Input  | `DATA_W` | Read data      |

## Parameters

```verilog
module mbist #(
    parameter DEPTH  = 1000,
    parameter DATA_W = 32,
    parameter ADDR_W = $clog2(DEPTH)
)
```

| Parameter |         Default | Description            |
| --------- | --------------: | ---------------------- |
| `DEPTH`   |          `1000` | Number of memory words |
| `DATA_W`  |            `32` | Data width             |
| `ADDR_W`  | `$clog2(DEPTH)` | Address width          |

## Error detection

Полученные данные сравниваются с ожидаемыми:

```verilog
check_mask = mem_rdata ^ expected_data;
```

Если:

```verilog
check_mask != 0
```

обнаружена ошибка.

При этом:

* `fail` — факт ошибки;
* `fail_addr` — адрес последней ошибки;
* `fail_data_mask` — битовая маска ошибки (`1` означает несовпадение соответствующего бита).

## FSM

```text
S_IDLE → S_M0 → S_M1 → S_M2 → S_DONE
```

`start` запускает тест из `S_IDLE`, `done` устанавливается в `S_DONE`.


## Notes

* `rst` — синхронный.
* После завершения теста для повторного запуска требуется сброс.
* Предполагается однократная задержка `mem_rdata` относительно операции чтения.
* `fail_addr` и `fail_data_mask` хранят последнюю обнаруженную ошибку.
* Реализованный алгоритм является March-подобным и не претендует на полное покрытие всех возможных memory fault models.
