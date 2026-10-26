#pragma once
#include <stdint.h>
typedef struct QBEngine QBEngine;
QBEngine *qb_create(void);
void qb_destroy(QBEngine *engine);
int qb_load(QBEngine *engine, int band, int side, const char *path);
int qb_prepare(QBEngine *engine);
uint64_t qb_underruns(QBEngine *engine);
void qb_level(QBEngine *engine, int band, double level);
void qb_master(QBEngine *engine, double volume);
void qb_width(QBEngine *engine, double width);
void qb_dynamics(QBEngine *engine, int enabled);
void qb_render(QBEngine *engine, float *left, float *right, uint32_t count);
