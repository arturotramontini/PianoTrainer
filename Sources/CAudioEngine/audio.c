#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <math.h>
#include <stdint.h>
#include <mach/mach_time.h>
#include <stdatomic.h>
#include <mach/mach_time.h>

#define MAX_NOTES 64

// #define INPUT_BUF 16384
// #define INPUT_BUF 32768
#define INPUT_BUF 65536
#define OUTPUT_BUF 65536


#define Ksr 44100
// #define Ksr 48000
// #define Ksr 96000
// #define Ksr 96000



//------------------------------------
// NOTE (synth)
//------------------------------------
typedef struct {
    double freq;
    
		double phase;
    double phase3;
    double phase5;
    double phase7;
    double phase9;
    double phase11;
    double phase13;

    double t;
    int state;
    double release_t;
    double release_start_env;
    double current_env;
		double velocity;
		double envSmooth;
		uint8_t nota;
		double sampleLP;
		uint32_t sustainOff;
} Note;

static Note notes[MAX_NOTES];
static int voiceIndex = 0;
static double kvn = 2.2; // 2..4  più alto più marcato esponeziale volume   velocity midi


//------------------------------------
// PARAMETRI VARI
//------------------------------------

#define MAX_PARAM 256
static _Atomic double parameters[MAX_PARAM];
// 0 : non usat0
// 1 : sustain value 1..500
// 2 : modulazione frequenza : frequency
// 3 : modulazione frequenza : amplitude



//-------------------------
static mach_timebase_info_data_t timebase;

void initTimer() {
    mach_timebase_info(&timebase);
}

double nowMicroseconds() {
    uint64_t t = mach_absolute_time();

    // converte in nanosecondi
    double ns = (double)t * (double)timebase.numer /
                (double)timebase.denom;

    return ns / 1000.0;
}
//-------------------------





//-------------------------

static double sustain = 500.0;
static double ModulationFrequency = 7.83;
static double ModulationAmplitude = 0.03; 



void setParameters(){
//-------
	sustain = parameters[1];
	// if (sustain < 1.0){sustain = 1.0;}
	// if (sustain > 500){sustain = 500.0;}
	parameters[1] = sustain;
//-------
 ModulationFrequency = parameters[2];
 ModulationAmplitude = parameters[3];
//-------
}

void setDefault(){
	for (int i=0;i<MAX_PARAM;i++){
		parameters[i]=0;
	}
		parameters[1]=1.5; // gloabl sustain (low value= long time, high value (ex. 500) -> stop very fast)
		parameters[2]=7.83; // modulation frequency in Hertz ( 7.83: schuman frequency)
		parameters[3]=0.02; // modulation deep 0..1  0-> no modulation  1> max modulation
		parameters[4]=20.0; // VOLUME NOTE 0..20
		parameters[5]=90.0; // slider vr1
		parameters[10]=0.0; // semitono di trasposizione 0 ..  +/- 12 x keyboard
		parameters[10]=0.0; // semitono di trasposizione 0 ..  +/- 12 x midi keyboard
		setParameters();
}

void setValue1(uint32_t index, double value1){
	if (index > MAX_PARAM-1){
		index = MAX_PARAM-1;
	}
	if (index < 0){
		index = 0;
	}
	parameters[index] = value1;
	setParameters();
	return ;
}
double getValue1(uint32_t index){
	if (index > MAX_PARAM-1){
		index = MAX_PARAM-1;
	}
	if (index < 0){
		index = 0;
	}
	return parameters[index];
}
//-------------------------



//------------------------------------
// DEBUG
//------------------------------------
static UInt32 gFrames = 0;
static uint64_t gHostTime = 0;
static double   gSampleTime = 0;


//------------------------------------
// OUTPUT copy BUFFER (FFT)
//------------------------------------
static float outputBuf[OUTPUT_BUF];
static int writeOutIdxBuf = 0;


//------------------------------------
// INPUT BUFFER (FFT)
//------------------------------------
static float inputBuf[INPUT_BUF];
static int writeIdxBuf = 0;

//------------------------------------
// GETTERS
//------------------------------------
UInt32 getFrames() { return gFrames; }
uint64_t getHostTime() { return gHostTime; }
double getSampleTime() { return gSampleTime; }


//-------------------------
static double value1 = 0;
void setValue(double value){
	value1 = value;
	return ;
}
double getValue(){
	// double v = (double)(rand())/RAND_MAX;
	// value1 = v;
	return value1;
}
//-------------------------


// //-------------------------
// static double sustain = 500.0;
// void setValue1(double value){
// 	if (value < 1.0){value = 1.0;}
// 	if (value > 500){value = 500.0;}
// 	sustain = value;
// 	return ;
// }
// double getValue1(){
// 	// double v = (double)(rand())/RAND_MAX;
// 	// value1 = v;
// 	return sustain;
// }
// //-------------------------


typedef struct {
    double t_prev;
    double t_start;
    double t_end;
    double duration;
		// uint64_t hostTime;   // 🔥 NUOVO
    uint32_t frames;
    uint32_t frameCounter;
    uint32_t offset;          // 🔥 calcolato nel callback
    double t01HT; // = hostTimeToSeconds(ts->mHostTime);
    double t02HT; // = hostTimeToSeconds(ts->mHostTime);
		double delta;
} AudioTiming;

static AudioTiming lastTiming;
static uint32_t frameCounter = 0;

double hostTimeToSeconds(uint64_t hostTime) {
    static mach_timebase_info_data_t info;
    if (info.denom == 0) {
        mach_timebase_info(&info);
    }
    return (double)hostTime * info.numer / info.denom / 1e9;
}

AudioTiming getLastTiming() {
    uint64_t now0 = mach_absolute_time();
	 double t0 = hostTimeToSeconds(now0);
	
	 lastTiming.delta = t0 - lastTiming.t_start;


    return lastTiming;
}

//-------------------------

// 👇 COPIA BUFFER PER GO
void getInputBuffer(float *out, int size) {
    int idx = writeIdxBuf;

    for (int i = 0; i < size; i++) {
        idx = (idx - 1 + INPUT_BUF) % INPUT_BUF;
        out[size - 1 - i] = inputBuf[idx];
    }
}

// 👇 COPIA BUFFER PER GO
void getOutputBuffer(float *out, int size) {
    int idx = writeOutIdxBuf;

    for (int i = 0; i < size; i++) {
        idx = (idx - 1 + OUTPUT_BUF) % OUTPUT_BUF;
        out[size - 1 - i] = outputBuf[idx];
    }
}


//------------------------------------
// NOTE CONTROL
//------------------------------------
// modifica da provare
// se è gia nel buffer, reimposta solo l'envelope all'inizio
void noteOn(double f,uint8_t nota, double velocity) {

		// for(int i = 0; i<MAX_NOTES; i++) {
		// 	if((notes[i].nota == nota) && (notes[i].state !=0)){
						
		// 		// printf("Nota già attiva: %d\n", notes[i].nota);
		// 				double v = notes[i].velocity / 128.0;
		// 				double amp = pow(v, kvn);   // prova 2.0, 2.2, 3.0
		// 				// printf("c Nota già attiva : %d   vel:%4.1f(%5.3f %5.3f)\n", notes[i].nota,notes[i].velocity,v,amp);

		// 		    notes[i].t = 0; // cambio solo il tempo per riattaccare l'envelope
		// 		    notes[i].state = 1; // forzo  anche lo stato a 1 : inizio suono
		// 				notes[i].velocity =velocity; // aggiorna però la velocity
						
		// 				// 🔥 AGGIUNGI QUESTO
		// 				// notes[i].envSmooth = notes[i].current_env;

		// 				return; // 🔥 IMPORTANTISSIMO
		// 	}
		// }

    int i = voiceIndex;
    voiceIndex = (voiceIndex + 1) % MAX_NOTES;

    notes[i].freq = f;
    notes[i].phase = 0;
    notes[i].phase3 = 0;
    notes[i].phase5 = 0;
    notes[i].phase7 = 0;
    notes[i].phase11 = 0;
    notes[i].phase13 = 0;

    notes[i].t = 0;
    notes[i].release_t = 0;
    notes[i].state = 1;
		
		// notes[i].phase = 0;//rand() * 2*M_PI / RAND_MAX;
		// notes[i].phase = (((double)rand() / RAND_MAX) * 2-1) * (M_PI * 0.9);  // +/- piccolo angolo di partenza

		notes[i].nota = nota;
		notes[i].velocity = velocity;
		notes[i].envSmooth = 0;


		double v = notes[i].velocity / 128.0;
		double amp = pow(v, kvn);   // prova 2.0, 2.2, 3.0
		// printf("c Nota : %d   vel:%5.1f(%5.3f %5.3f)\n", notes[i].nota,notes[i].velocity,v,amp);


}

// void noteOff2(double f) {
//     for (int i = 0; i < MAX_NOTES; i++) {
//         if (notes[i].state == 1 && fabs(notes[i].freq - f) < 0.01) {
// 					// printf("richiesta nota off per frequenza: %5.1f\n",f);
//             notes[i].state = 2;
//             notes[i].release_t = 0;
//             notes[i].release_start_env = notes[i].current_env;
//         }
//     }
// }

void noteOff1(uint8_t nota, uint32_t sustainOff) {
    for (int i = 0; i < MAX_NOTES; i++) {
        if (notes[i].state == 1 && notes[i].nota == nota) {
					// printf("richiesta nota off per frequenza: %5.1f\n",f);
            notes[i].state = 2;
            notes[i].release_t = 0;
            notes[i].sustainOff = sustainOff;
            // notes[i].release_start_env = notes[i].current_env;
        }
    }
}


//------------------------------------
// BUFFER circolare di comunicazione
//------------------------------------
#define MAX_EVENTS 256
// #define MAX_EVENTS 16 // per debug

typedef struct {
		// uint8_t inProgress;
    int type; // 1 = noteOn, 2 = noteOff
    double freq;
    uint8_t nota;
    double velocity;
		uint32_t sustainOff;
} Event;

static Event queue[MAX_EVENTS];
// static volatile int writeIdx = 0;
// static volatile int readIdx = 0;
static atomic_int writeIdx = 0;
static atomic_int readIdx = 0;


// void enqueueNoteOn(double f, uint8_t nota, double velocity) {
//     int next = (writeIdx + 1) % MAX_EVENTS;

//     // buffer pieno → scarta (importante: non bloccare!)
//     if (next == readIdx) {
//         return;
//     }

//     queue[writeIdx].type = 1;
//     queue[writeIdx].freq = f;
//     queue[writeIdx].nota = nota;
//     queue[writeIdx].velocity = velocity;

//     writeIdx = next;
// }
void enqueueNoteOn(double f, uint8_t nota, double velocity) {
    int w = atomic_load_explicit(&writeIdx, memory_order_relaxed);
    int r = atomic_load_explicit(&readIdx, memory_order_acquire);

    int next = (w + 1) % MAX_EVENTS;
    if (next == r) return; // pieno

		// printf("enqueue ON  w=%d r=%d\n", w, r);
		
		// queue [w].inProgress = 1;
    // scrivi dati
    queue[w].type = 1;
    queue[w].freq = f;
    queue[w].nota = nota;
    queue[w].velocity = velocity;

		// queue [w].inProgress = 2;
    

    // 🔥 PUBBLICA l'evento (importantissimo)
    atomic_store_explicit(&writeIdx, next, memory_order_release);
}


// void enqueueNoteOff(uint8_t nota) {
//     int next = (writeIdx + 1) % MAX_EVENTS;

//     if (next == readIdx) return;

//     queue[writeIdx].type = 2;
//     queue[writeIdx].nota = nota;

//     writeIdx = next;
// }


void enqueueNoteOff( uint8_t nota, uint32_t sustainOff) {
    int w = atomic_load_explicit(&writeIdx, memory_order_relaxed);
    int r = atomic_load_explicit(&readIdx, memory_order_acquire);

    int next = (w + 1) % MAX_EVENTS;
    if (next == r) return; // pieno

		// printf("enqueue OFF w=%d r=%d\n", w, r);
		
		// queue [w].inProgress = 1;

    // scrivi dati
    queue[w].type = 2;
    queue[w].nota = nota;
		queue[w].sustainOff = sustainOff;

		// queue [w].inProgress = 2;

    // 🔥 PUBBLICA l'evento (importantissimo)
    atomic_store_explicit(&writeIdx, next, memory_order_release);
}





// void processEvents() {
//     while (readIdx != writeIdx) {
//         Event *e = &queue[readIdx];

//         if (e->type == 1) {
//             noteOn(e->freq, e->nota, e->velocity);
//         } else if (e->type == 2) {
//             noteOff1(e->nota);
//         }

//         readIdx = (readIdx + 1) % MAX_EVENTS;
//     }
// }




void processEvents() {
    int r = atomic_load_explicit(&readIdx, memory_order_relaxed);
    int w = atomic_load_explicit(&writeIdx, memory_order_acquire);

    while (r != w) {
        Event *e = &queue[r % MAX_EVENTS];

				// if (e->inProgress != 2){
				// 	return;
				// }

        if (e->type == 1) {
            noteOn(e->freq, e->nota, e->velocity);
        }

				if (e->type == 2) {
            noteOff1(e->nota,e->sustainOff);
						
        }

	
        r = (r + 1) % MAX_EVENTS;

				// printf("process r=%d w=%d   tipo:%d\n", r, w,e->type); // per debug
				// if (e->type == 2){
				// 	printf("\n");
				// }
    }

    atomic_store_explicit(&readIdx, r, memory_order_release);
}


//------------------------------------
// SIMPLE LOW PASS FILTER
//------------------------------------

static int first_lp = 0;

typedef struct {
    double y;      // stato interno
    double alpha;  // coefficiente
} LPF;

static LPF lpf_4k;

void lpf_init(LPF *f, double fc, double fs) {
    double x = -2.0f * M_PI * fc / fs;
    f->alpha = 1.0f - expf(x);
    f->y = 0.0f;
}

double lpf_process(LPF *f, double x) {
    f->y += f->alpha * (x - f->y);
    return f->y;
}
//------------------------------------
// END OF SIMPLE LOW PASS FILTER
//------------------------------------


//------------------------------------
// OUTPUT CALLBACK (synth)
//------------------------------------
//---------------
static double tmax = 0;
static double gain = 1;
double getTmax(){
	double t = tmax;
	tmax = 0;
	return t;
}
void setGain(double g){
	gain = g;
}
//---------------

OSStatus renderCallback(
    void *inRefCon,
    AudioUnitRenderActionFlags *flags,
    const AudioTimeStamp *ts,
    UInt32 bus,
    UInt32 frames,
    AudioBufferList *ioData
) {

	double t1a = nowMicroseconds();

//-------------------------
if (first_lp == 0){
	first_lp=1;
	// α≈1−e−2π⋅4000/48000  ≈ 0.39
	// α≈1−e−2π⋅800/44100  ≈ 0.39
// 800Hz, 44100Hz, -0,113980685844528

	// lpf_4k.alpha = -0,113980685844528;
	// lpf_4k.y = 800.0;

	// lpf_init(LPF *f, float fc, float fs) 
	// lpf_init(&lpf_4k, 800, 44100); 
	lpf_init(&lpf_4k, 400, 44100); 
}
//-------------------------



		frameCounter ++;

    uint64_t now0 = mach_absolute_time();
		double t0 = hostTimeToSeconds(now0);
		double t01HT = hostTimeToSeconds(ts->mHostTime);


	 

		double envTarget = 0;
		double dt = 0;
		double tau = 0;
		double alpha = 0;
		// static double envSmooth = 0;


    float *buffer = (float *)ioData->mBuffers[0].mData;


		// buffer[0] = (float)(0.8); // per debug


    // double sr = 44100.0;
    // double sr = 48000.0;
    double sr = Ksr;

		dt = 1.0 / sr; //44100.0;
		// tau = 0.005;
		tau = 0.002;
		// tau = 0.01;
		//alpha = dt / tau;   // circa 0.0045
		alpha = 1 - exp(-dt/tau);


    gFrames = frames;
		parameters[6] = (double)frames;

    gHostTime = ts->mHostTime;
    gSampleTime = ts->mSampleTime;

		value1 = (double) frames;

    for (UInt32 i = 0; i < frames; i++) {
        double mix = 0;
				// int flag = 0;
   			
				processEvents(); // 🔥 QUI


        for (int n = 0; n < MAX_NOTES; n++) {

            double env = 0;


            if (notes[n].state == 1) {

							// if (flag==0){
							// 	flag=1; // la prima nota disponibile
							// }

                // env = exp(-1.3 * notes[n].t) * (1.0 - exp(-200.0 * notes[n].t));
                // env = exp(-15.0 * notes[n].t) * (1.0 - exp(-200.0 * notes[n].t));
                
								// envTarget = exp(-1.3 * notes[n].t) * (1.0 - exp(-200.0 * notes[n].t));
								// envTarget = exp(-0.73 * notes[n].t) * (1.0 - exp(-400.0 * notes[n].t));
								envTarget = exp(-1.0 * notes[n].t) * (1.0 - exp(-2000.0 * notes[n].t));
								// envTarget = pow(2,(-1.0 * notes[n].t)) * (1.0 - pow(2,(-2000.0 * notes[n].t)));
                
								

								// dt = 1.0 / 44100.0;
								// tau = 0.005;
								// //alpha = dt / tau;   // circa 0.0045
								// alpha = 1 - exp(-dt/tau);

								// smoothing
								notes[n].envSmooth += alpha * (envTarget - notes[n].envSmooth);
								env = notes[n].envSmooth;


// prova di debug -- senza eenv --
// env = 1;


								notes[n].current_env = env;
                notes[n].release_start_env = env;


            }

            if (notes[n].state == 2) {

							// if (flag==1){
							// 	flag=2; // la prima nota off disponibile
							// }

							double sus = sustain;
							if (notes[n].sustainOff != 0){
								sus = notes[n].sustainOff;
							}


                env = notes[n].release_start_env *
                      exp(-sus * notes[n].release_t); // smorza prima se piu alto
                      // exp(-500.0 * notes[n].release_t); // smorza prima se piu alto
                      // // exp(-190.0 * notes[n].release_t); // smorza prima se piu alto
                      // exp(-90.0 * notes[n].release_t); // smorza prima se piu alto
                      // exp(-30.0 * notes[n].release_t); // smorza prima se piu alto
                      // exp(-8.0 * notes[n].release_t); // smorza prima se piu alto
                      //  exp(-1.0 * notes[n].release_t); // tipo sustain
                      // exp(-0.5 * notes[n].release_t); // tipo sustain
                      // exp(-3.0 * notes[n].release_t); // tipo sustain
                      // exp(-2.0 * notes[n].release_t);
                      // exp(-5.0 * notes[n].release_t);


// sempre prova di debug env = 0
// env = 0;



                notes[n].release_t += 1.0 / sr;

                if (env < 0.01) {
                    notes[n].state = 0;
										// flag = 1;
                    continue;
                }
            }

            if (notes[n].state != 0) {

							//  notes[n].envSmooth += alpha * (envTarget - notes[n].envSmooth);


								// //gestione velocity
								double vel = notes[n].velocity/128.0; // normalizza 0..1
								// kvn = 3;
								// double amp = pow(vel, kvn);   // prova 2.0, 2.2, 3.0
								// // double amp = (log(5*vel+1)/log(2))/3; // modo logaritmo, non va bene
								// amp = 0.4+amp*3		;
								// if(amp > 1.5)  amp = 1.5 ;
								// // double amp = 1.0; // bypasso che fa un pò cagare il v elocity di Korg nanoKEY2:)

								// //env = env * amp;


								env = env * vel ; //*1.25;





								// partenza primi 5 msec soft , dredo...
								notes[n].envSmooth += alpha * (env - notes[n].envSmooth);
							 	double env1 = notes[n].envSmooth;

								

								// compensazione per frequenze basse
								double lfc = notes[n].freq;
								lfc = log(lfc)/log(4);
								// lfc /= 4;
								// lfc = 2- lfc; // qui diventa ~ 1,8 a 10Hz e 1 a 4000Hz
								lfc /= 1;
								lfc = 7- lfc; // qui diventa ~ 7 a 1Hz e 1 a 4000Hz

								// c'è qualcosa che non và, pare diminuire invece che aumentare sotto certe basse frequenza
								// env *= lfc;	
								// per ora rimuovo
								//-------------------------

                // mix += sin(notes[n].phase) * env1 ;

								double freq = notes[n].freq;

								







								// double freqSHUM = sin(2*M_PI * 7.83);
								// freqSHUM*=1;

double  freq_p = parameters[2];
double  freq_a = parameters[3];



								// double freqSCHUMMAN = sin(2*M_PI * 7.83/1 * notes[n].t); // 4 Hertz (not thr schumann fundamental)
								// freq *= (1 + 0.01*freqSCHUMMAN); // fequency modulation
								double freqSCHUMMAN = sin(2*M_PI * freq_p * notes[n].t); // 4 Hertz (not thr schumann fundamental)
								freq *= (1 + freq_a * freqSCHUMMAN); // fequency modulation






								
								
								// small random noise, per ridurre battimenti
								//double r1 = (double)rand()/(double)RAND_MAX; // 0..1 Hz
								//double freqRand1 = 0.002*sin(M_PI/2 +2*M_PI * r1 ); // 4 Hertz (not thr schumann fundamental)
								// freq *= (1 + freqRand1);

								
								// freq = baseFreq * (1 + 0.001*sin(2π * 0.2 * t))
								// freq *= (1+0.001*sin(2*M_PI * 0.2 * notes[n].t));
								// freq = freq + (double)(rand()) / RAND_MAX;

                // notes[n].phase += 2.0 * M_PI * notes[n].freq / sr;
                // notes[n].phase += 2.0 * M_PI * freq / sr;



								//-------------------------------------  aggiorna campione del sample 
								double w = 2.0 * M_PI * freq / sr;



								// i moltiplicatori sono  ridotti all'intervallo 1 .. <2
								notes[n].phase  += w * 1.00;
								notes[n].phase3 += w * 1.50; //3;
								notes[n].phase5 += w * 1.25; //5
								notes[n].phase7 += w * 1.75; //7;
								notes[n].phase9 += w * 1.125; //9;
								notes[n].phase11 += w * 1.375; //11.0;
								notes[n].phase13 += w * 1.625; //13.0;


                // limita ,  magari anche in più cicli, a 0..2pi
								if (notes[n].phase > 2*M_PI)   notes[n].phase -= 2*M_PI;
								if (notes[n].phase3 > 2*M_PI)  notes[n].phase3-= 2*M_PI;
								if (notes[n].phase5 > 2*M_PI)  notes[n].phase5 -= 2*M_PI;
								if (notes[n].phase7 > 2*M_PI)  notes[n].phase7 -= 2*M_PI;
								if (notes[n].phase9 > 2*M_PI)  notes[n].phase9 -= 2*M_PI;
								if (notes[n].phase11 > 2*M_PI)  notes[n].phase11 -= 2*M_PI;
								if (notes[n].phase13 > 2*M_PI)  notes[n].phase13 -= 2*M_PI;
								//---------------------



              	// output = somma delle sinusoidi
								double sample =
										 1.00 * sin(notes[n].phase)  +
										 0.00 * sin(notes[n].phase3) +
										 0.00 * sin(notes[n].phase5) + 
										 0.00 * sin(notes[n].phase7) +
										 0.00 * sin(notes[n].phase9) +
										 0.00 * sin(notes[n].phase11)+
										 0.00 * sin(notes[n].phase13);

										// 2.0 * sin(notes[n].phase) * env +
										// 0.0 * sin(notes[n].phase2) * env  +
										//  0.0 * sin(notes[n].phase3) * env  +
										//  0.0 * sin(notes[n].phase4) * env  +
										//  0. * sin(notes[n].phase5) * env ;
										//  0. * sin(notes[n].phase6) * env ;
										//  0. * sin(notes[n].phase7) * env ;
										//  0. * sin(notes[n].phase8) * env ;
										//  0. * sin(notes[n].phase9) * env ;
										//  0. * sin(notes[n].phase10) * env ;
										//  0. * sin(notes[n].phase11) * env ;
										//  0. * sin(notes[n].phase12) * env ;
										//  0. * sin(notes[n].phase13) * env ;

										 
										 sample *= env;




							//  sample = sin(notes[n].phase) * env ;

// sample *= env1;



//  sample *= freqSCHUMMAN; // amplitude modulation





// uso se voglio modulazione ampiezza, inquesto caso a1 Hz.
								//double freq0d1Hz = sin(M_PI/2 +2*M_PI * 1 * notes[n].t); // 4 Hertz (not thr schumann fundamental)
								// sample *= freq0d1Hz; // amplitude modulation







                mix += sample  ;



            }

					

            notes[n].t += 1.0 / sr;
        }

				// double level = sqrt(mean(mix*mix));

        // buffer[i] = (float)(mix * 0.1 );
        // buffer[i] = (float)(mix * 0.02 );
        // buffer[i] = (float)(mix * 0.03 );
//				buffer[i] = (float)(mix * 0.03);



        double mixValue = lpf_process(&lpf_4k, (mix * 0.03));
  			buffer[i] = (float)(mixValue);

				// buffer[i] *= 20.0; //dovrebbe essere il volume finale
				buffer[i] *= parameters[4]; //dovrebbe essere il volume finale
 


//-------------------				
// static float outputBuf[OUTPUT_BUF];
// static int writeOutIdxBuf = 0;
outputBuf[writeOutIdxBuf]= buffer[i];
writeOutIdxBuf = (writeOutIdxBuf + 1) % OUTPUT_BUF;
//-------------------

				// marcatore inizio frame
				// if (i < 1){
				// 		buffer[i] = (float)(-0.2);
				// }
    }

    uint64_t now = mach_absolute_time();
    double t1 = hostTimeToSeconds(now);

    lastTiming.t_prev = lastTiming.t_start ;
    lastTiming.t_start = t0;
    lastTiming.t_end = t1;
    lastTiming.duration = t1 - t0;
    lastTiming.frames = frames;
    lastTiming.frameCounter = frameCounter;
		// lastTiming.hostTime = now0;
    lastTiming.t02HT = lastTiming.t01HT;
    lastTiming.t01HT = t01HT;

		if((t1-t0)> tmax){
			tmax =  t1-t0;
		}


    double t2a = nowMicroseconds();
    parameters[8] = t2a - t1a;


    return noErr;
}

//------------------------------------
// INPUT CALLBACK (microfono)
//------------------------------------
// OSStatus inputCallback(
//     void *inRefCon,
//     AudioUnitRenderActionFlags *flags,
//     const AudioTimeStamp *ts,
//     UInt32 bus,
//     UInt32 frames,
//     AudioBufferList *ioData
// ) {
//     // float data[2048];
// 		float *data = (float*)malloc(sizeof(float) * frames);

// 		// printf("INPUT frames: %d\n", (int)frames);
		
//     AudioBufferList buf;
//     buf.mNumberBuffers = 1;
//     buf.mBuffers[0].mNumberChannels = 1;
//     buf.mBuffers[0].mDataByteSize = sizeof(float) * frames;
//     buf.mBuffers[0].mData = data;

//     AudioUnit unit = (AudioUnit)inRefCon;

//     AudioUnitRender(unit, flags, ts, 1, frames, &buf);

//     // 👉 copia nel buffer circolare
//     for (UInt32 i = 0; i < frames; i++) {
//         inputBuf[writeIdx] = data[i];
//         writeIdx = (writeIdx + 1) % INPUT_BUF;
//     }
//    free(data);   // 👈 QUI
//     return noErr;
// }




OSStatus inputCallback(
    void *inRefCon,
    AudioUnitRenderActionFlags *flags,
    const AudioTimeStamp *ts,
    UInt32 bus,
    UInt32 frames,
    AudioBufferList *ioData
) {

    // return noErr;
		double t1a = nowMicroseconds();

    AudioUnit unit = (AudioUnit)inRefCon;

    static int16_t data[2048];  // buffer statico sicuro

		// static AudioBufferList buf;
    // buf.mNumberBuffers = 1;
    // buf.mBuffers[0].mNumberChannels = 1;
    // buf.mBuffers[0].mDataByteSize = sizeof(float) * frames;
    // buf.mBuffers[0].mData = data;

		static AudioBufferList buf = {
				.mNumberBuffers = 1,
				.mBuffers[0] = {
						.mNumberChannels = 1,
						.mDataByteSize = 0,
						.mData = NULL
				}
		};
		
		if (frames > 2048) return noErr;

		// buf.mBuffers[0].mDataByteSize = sizeof(float) * frames;
		buf.mBuffers[0].mDataByteSize = sizeof(int16_t) * 2048;
		buf.mBuffers[0].mData = data;

		
		static int cnt = 0;
		// if (++cnt % 50 == 0) {
		// 		printf("sample=%d\n", data[0]);
		// }		
		// if (cnt < 50 ) {
		// 		printf("sample=%d\n", data[0]);
		// }


    // OSStatus err = AudioUnitRender(unit, flags, ts, 1, frames, &buf);
		OSStatus err = AudioUnitRender(unit, flags, ts, bus, frames, &buf);
    if (err != noErr) {
        printf("Render error: %d\n", err);
        return err;
    }

		parameters[7] = (double)frames;

    for (UInt32 i = 0; i < frames; i++) {
        inputBuf[writeIdxBuf] = data[i] /32768.0f;
        writeIdxBuf = (writeIdxBuf + 1) % INPUT_BUF;
    }

    // printf("sample=%f\n", data[0]);
    // printf("frames=%d \n", frames);
		// printf("bus:%d\n",bus);


		    double t2a = nowMicroseconds();
    parameters[9] = t2a - t1a;

    return noErr;
}







// OSStatus inputCallback(
//     void *inRefCon,
//     AudioUnitRenderActionFlags *flags,
//     const AudioTimeStamp *ts,
//     UInt32 bus,
//     UInt32 frames,
//     AudioBufferList *ioData
// ) {
//     float *data = (float*)ioData->mBuffers[0].mData;

//     if (!data) {
//         printf("no data!\n");
//         return noErr;
//     }

//     for (UInt32 i = 0; i < frames; i++) {
//         inputBuf[writeIdx] = data[i];
//         writeIdx = (writeIdx + 1) % INPUT_BUF;
//     }

//     printf("sample=%f\n", data[0]);

//     return noErr;
// }

// OSStatus inputCallback(
//     void *inRefCon,
//     AudioUnitRenderActionFlags *flags,
//     const AudioTimeStamp *ts,
//     UInt32 bus,
//     UInt32 frames,
//     AudioBufferList *ioData
// ) {
//     float data[8192];
//     // float data[2048];
// 		// float *data = (float*)malloc(sizeof(float) * frames);

// 		// printf("INPUT frames: %d\n", (int)frames);
		



//     AudioBufferList buf;
//     buf.mNumberBuffers = 1;
//     buf.mBuffers[0].mNumberChannels = 1;
//     buf.mBuffers[0].mDataByteSize = sizeof(float) * frames;
//     buf.mBuffers[0].mData = data;

//     AudioUnit unit = (AudioUnit)inRefCon;

//     // AudioUnitRender(unit, flags, ts, 1, frames, &buf);
// 		OSStatus err = AudioUnitRender(unit, flags, ts, 1, frames, &buf);
// 		if (err != noErr) {
// 				printf("Render error: %d\n", err);
// 		}

//     // 👉 copia nel buffer circolare
//     for (UInt32 i = 0; i < frames; i++) {
//         inputBuf[writeIdx] = data[i];
//         writeIdx = (writeIdx + 1) % INPUT_BUF;
//     }
// 		// printf("writeIdx: %d\n", (int)writeIdx);
// 		// printf("data: %4.1f\n", data[0]);
// // printf("frames=%d sample=%f\n", (int)frames, data[0]);

//   //  free(data);   // 👈 QUI
//     return noErr;
// }








//------------------------------------
// START AUDIO (OUTPUT + INPUT)
//------------------------------------
void startAudio() {

	printf("start\n");

	initTimer();

    //------------------------------------
    // OUTPUT (synth)
    //------------------------------------
    AudioComponentDescription desc = {0};
    desc.componentType = kAudioUnitType_Output;
    
		// desc.componentSubType = kAudioUnitSubType_DefaultOutput;
		desc.componentSubType = kAudioUnitSubType_HALOutput;

    desc.componentManufacturer = kAudioUnitManufacturer_Apple;

    AudioComponent comp = AudioComponentFindNext(NULL, &desc);
    AudioUnit outUnit;
    AudioComponentInstanceNew(comp, &outUnit);

    AURenderCallbackStruct cb;
    cb.inputProc = renderCallback;

    AudioUnitSetProperty(outUnit,
        kAudioUnitProperty_SetRenderCallback,
        kAudioUnitScope_Input,
        0,
        &cb,
        sizeof(cb));

		UInt32 disable = 0;
		AudioUnitSetProperty(outUnit,
				kAudioOutputUnitProperty_EnableIO,
				kAudioUnitScope_Input,
				1,
				&disable,
				sizeof(disable));

    AudioStreamBasicDescription fmt = {0};
    // fmt.mSampleRate = 44100;
    // fmt.mSampleRate = 48000;
    fmt.mSampleRate = Ksr;
    fmt.mFormatID = kAudioFormatLinearPCM;
    fmt.mFormatFlags = kAudioFormatFlagIsFloat;
    fmt.mChannelsPerFrame = 1;
    fmt.mBitsPerChannel = 32;
    fmt.mBytesPerFrame = 4;
    fmt.mFramesPerPacket = 1;
    fmt.mBytesPerPacket = 4;

    AudioUnitSetProperty(outUnit,
        kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Input,
        0,
        &fmt,
        sizeof(fmt));

    AudioUnitInitialize(outUnit);
    AudioOutputUnitStart(outUnit);


	printf("start 2 \n");


    //------------------------------------
    // INPUT (microfono)
    //------------------------------------
    AudioComponentDescription inDesc = {0};
    inDesc.componentType = kAudioUnitType_Output;

    inDesc.componentSubType = kAudioUnitSubType_HALOutput;
		// inDesc.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    
		inDesc.componentManufacturer = kAudioUnitManufacturer_Apple;

    AudioComponent inComp = AudioComponentFindNext(NULL, &inDesc);


	printf("start 2a \n");



    AudioUnit inUnit;
    AudioComponentInstanceNew(inComp, &inUnit);

	printf("start 2b \n");



		AudioDeviceID device = 0;
		UInt32 size = sizeof(device);

		AudioObjectPropertyAddress addr = {
				kAudioHardwarePropertyDefaultInputDevice,
				kAudioObjectPropertyScopeGlobal,
				kAudioObjectPropertyElementMain
		};

		AudioObjectGetPropertyData(
				kAudioObjectSystemObject,
				&addr,
				0,
				NULL,
				&size,
				&device
		);





	printf("start 3 \n");





		// enable input
    UInt32 enable = 1;
    AudioUnitSetProperty(inUnit,
        kAudioOutputUnitProperty_EnableIO,
        kAudioUnitScope_Input,
        1,
        &enable,
        sizeof(enable));


			// disable output  
		UInt32 disable1 = 0;
		AudioUnitSetProperty(inUnit,
				kAudioOutputUnitProperty_EnableIO,
				kAudioUnitScope_Output,
				0,
				&disable1,
				sizeof(disable1));



			// device  
			AudioUnitSetProperty(inUnit,
					kAudioOutputUnitProperty_CurrentDevice,
					kAudioUnitScope_Global,
					0,
					&device,
					sizeof(device));
			
			  


			// format
			AudioStreamBasicDescription inFmt = {0};
			// inFmt.mSampleRate = 44100;
			// inFmt.mSampleRate = 48000;
			inFmt.mSampleRate = Ksr;
			inFmt.mFormatID = kAudioFormatLinearPCM;
			// inFmt.mFormatFlags = kAudioFormatFlagIsFloat;
			// inFmt.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
			inFmt.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
			inFmt.mChannelsPerFrame = 1;
			inFmt.mBitsPerChannel = 16;
			inFmt.mBytesPerFrame = 2;
			inFmt.mFramesPerPacket = 1;
			inFmt.mBytesPerPacket = 2;



			// // format
			// AudioStreamBasicDescription inFmt = {0};
			// inFmt.mSampleRate = 44100;
			// inFmt.mFormatID = kAudioFormatLinearPCM;
			// // inFmt.mFormatFlags = kAudioFormatFlagIsFloat;
			// // inFmt.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
			// inFmt.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
			// inFmt.mChannelsPerFrame = 1;
			// inFmt.mBitsPerChannel = 32;
			// inFmt.mBytesPerFrame = 4;
			// inFmt.mFramesPerPacket = 1;
			// inFmt.mBytesPerPacket = 42;



			AudioUnitSetProperty(inUnit,
					kAudioUnitProperty_StreamFormat,
					kAudioUnitScope_Output,   // ⚠️ IMPORTANTISSIMO
					1,                        // ⚠️ bus input
					&inFmt,
					sizeof(inFmt));



			// AudioUnitSetProperty(inUnit,
			// 		kAudioUnitProperty_StreamFormat,
			// 		kAudioUnitScope_Input,   // 🔥 QUESTO MANCAVA
			// 		0,
			// 		&inFmt,
			// 		sizeof(inFmt));



				AURenderCallbackStruct inCB;
				inCB.inputProc = inputCallback;
				inCB.inputProcRefCon = inUnit;

				AudioUnitSetProperty(inUnit,
						kAudioOutputUnitProperty_SetInputCallback,
						kAudioUnitScope_Global,
						0,
						&inCB,
						sizeof(inCB));

				UInt32 flag = 0;
				AudioUnitSetProperty(inUnit,
						kAudioUnitProperty_ShouldAllocateBuffer,
						kAudioUnitScope_Output,
						1,  // bus input
						&flag,
						sizeof(flag));


    // AudioUnitInitialize(inUnit);
    // AudioOutputUnitStart(inUnit);


OSStatus err;

err = AudioUnitInitialize(inUnit);
printf("init err = %d\n", err);

err = AudioOutputUnitStart(inUnit);
printf("start err = %d\n", err);


UInt32 isRunning = 0;
UInt32 size1 = sizeof(isRunning);

AudioUnitGetProperty(inUnit,
    kAudioOutputUnitProperty_IsRunning,
    kAudioUnitScope_Global,
    0,
    &isRunning,
    &size1);

printf("running = %d\n", (int)isRunning);

UInt32 size2 = sizeof(UInt32);
UInt32 alive = 0;

AudioObjectPropertyAddress addr2 = {
    kAudioDevicePropertyDeviceIsAlive,
    kAudioObjectPropertyScopeInput,
    kAudioObjectPropertyElementMain
};

AudioObjectGetPropertyData(device, &addr2, 0, NULL, &size2, &alive);

printf("device alive = %d\n", (int)alive);


}