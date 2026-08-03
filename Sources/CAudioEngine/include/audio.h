#ifndef AUDIO_H
#define AUDIO_H

#include <stdint.h>

void startAudio();
void noteOn(double f,uint8_t nota,double velocity);
void noteOff2(double f);
void noteOff1(uint8_t nota) ;

// debug
uint32_t getFrames(void);
uint64_t getHostTime(void);
double   getSampleTime(void);

// 👇 NUOVO
void getInputBuffer(float *out, int size);
void getOutputBuffer(float *out, int size); 
int getOutputBufferStream(float *out, int size); 

void setValue(double value);
double getValue();
double nowMicroseconds() ;
// void setValue1(double value);
// double getValue1();
// void setValue1(uint32_t index, double value1, double value2);
// void getValue1(uint32_t index);

void setValue1(uint32_t index, double value1);
double getValue1(uint32_t index);
void setDefault();


// old type
// typedef struct {
//     double t_start;
//     double t_end;
//     double duration;
//     uint32_t frames;
// } AudioTiming;

typedef struct {
    double t_prev;
    double t_start;
    double t_end;
    double duration;
		// uint64_t hostTime;   // 🔥 NUOVO
    uint32_t frames;
    uint32_t frameCounter;
		uint32_t offset;
		double t01HT;
		double t02HT;
		double delta;
} AudioTiming;

AudioTiming getLastTiming();


void enqueueNoteOn(double f, uint8_t nota, double velocity);
// void enqueueNoteOff(uint8_t nota) ;
void enqueueNoteOff( uint8_t nota, uint32_t sustainOff) ;
double getTmax();
void setGain(double g);



#endif