#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Hatice Rana BOZ
//23100011069
//Eczane otomasyonu


int cvp,ilacsayisi,i,crp=0;

typedef struct ilac
{
    char ilac_adi[20];
    char ilac_turu[20];
    char firma_adi[20];
    int fiyat;
    int skt; //son kullanma tarihi
    int kutu_adedi;

} ILC;
typedef struct hasta
{
    char hasta_adi[20];
    double  tc_no;
    int recete_no;
    ILC*ilaclar;

} HST;

void listele(); //listeleme yapmak için fonksiyon
ILC* ekleme(); //Kayit yapmak için fonksiyon
void satis(); //satis icin fonksiyon
void guncelleme(); //kayitlari güncelliyebilmek için fonksiyon
int menu(); //istedigimiz zaman menüyü çagirabilmek için menü fonksiyonu
int reset(); //programý sýfýrlayack


int main()
{



    int secim; //menüden seçilen
    secim=menu();

    if(secim==1)

    ekleme();

    if(secim==2)

        satis();

    if(secim==3)

        guncelleme();

    if(secim==4)
    {
        ILC*ilaclar;

        listele( ilacsayisi,ilaclar);
    }



    if(secim==5)

        reset();
    if(secim==6)

        return ilacsayisi;
}
int maintwo()
{
    int secim; //menüden seçilen
    secim=menu();
    if(secim==1)

        ekleme();

    if(secim==2)

        satis();

    if(secim==3)

        guncelleme();

    if(secim==4)
    {
        ILC*ilaclar;

        listele( ilacsayisi,ilaclar);
    }



    if(secim==5)

        reset();

    return ilacsayisi;
}

int menu(int secim)
{
    printf("    *ECZANEMIZE HOSGELDINIZ*\n");
    printf("-------------MENU-------------\n");
    printf("\t1. Ilac kayit\n");
    printf("\t2. Ilac satis\n");
    printf("\t3. Ilac guncelle\n");
    printf("\t4. Listele\n");
    printf("\t5. Reset\n");
    printf("------------------------------\n");
    printf(" Lutfen yapmak istediginiz islemin numarasini giriniz: ");
    scanf("%d",&secim);

    return secim;
}
ILC* ekleme()
{

    HST*hastalar;
    int i=0;
    printf(" Kac tane ilac gireceksiniz: ");
    scanf("%d",&ilacsayisi);


    ILC*ilaclar=(ILC*)malloc(sizeof(ILC)*ilacsayisi);


    for(i=0; i<ilacsayisi; i++)
    {
        printf(" %d. Ilacin adi giriniz:",i+1);
        scanf("%s",&ilaclar[i].ilac_adi);
        printf(" %d. Ilacin turu giriniz(surup,hap vb.):",i+1);
        scanf("%s",&ilaclar[i].ilac_turu);
        printf(" %d. Ilacin Firma adini giriniz:",i+1);
        scanf("%s",&ilaclar[i].firma_adi);
        printf(" %d. Ilacin kutu adedi giriniz:",i+1);
        scanf("%d",&ilaclar[i].kutu_adedi);
        printf(" %d. Ilacin Son kullanma yilini giriniz(YYYY):",i+1);
        scanf("%d",&ilaclar[i].skt);
        printf(" %d. Ilacin kutu fiyatini giriniz:",i+1);
        scanf("%d",&ilaclar[i].fiyat);
        printf("\n");



    }
    printf("\n");
    printf("\n Kayitiniz basariyla olusturulmustur.\n");
    printf(" Saglikli gunler dileriz.\n");
    printf("\n\n");

    printf("listelemek ister misiniz:\n 1-)EVET\t2-)HAYIR\n");
    scanf(" %d",&cvp);
     printf("\n");
    if(cvp==1)
    {
        printf("--------LISTE--------\n");
        for( i=0; i<ilacsayisi; i++)
        {
            printf("\n");
            printf(" %d. Ilacin  adi : %s\n",i+1,((ilaclar+i)->ilac_adi));
            printf(" %d. Ilacin turu : %s\n",i+1,(ilaclar+i)->ilac_turu);
            printf(" %d. Ilacin firma adi : %s\n",i+1,(ilaclar+i)->firma_adi);
            printf(" %d. Ilacin kutu adedi : %d\n",i+1,((ilaclar+i)->kutu_adedi));
            printf(" %d. Ilacin Son kullanma tarihi : %d\n",i+1,((ilaclar+i)->skt));
            printf(" %d. Ilacin kutu fiyati : %d\n",i+1,((ilaclar+i)->fiyat));
            crp=((ilaclar+i)->kutu_adedi)*((ilaclar+i)->fiyat);
            printf(" Toplam fiyat:%d*%dTL=%d",(ilaclar+i)->kutu_adedi,((ilaclar+i)->fiyat),crp);
        }
    }


    printf("\n\n");
    printf(" Ana Menuye donmek ister misiniz \n 1-)EVET\t2-)HAYIR\n");
    scanf(" %d",&cvp);
    printf("\n\n");
    if(cvp==1)
    {
        main();
    }
    if(cvp==2)
        printf(" Isleminiz bitmistir.\n Saglikli gunler dileriz.\n\n ");

    return ilacsayisi,ilaclar;
}
void satis(int ilacsayisi)
{
    int hstsayisi,i,j;
    printf(" Hasta sayisi kac: ");
    scanf("%d",&hstsayisi);
    HST*hastalar=(HST*)malloc(sizeof(HST)*hstsayisi);

    (hastalar+i)->ilaclar=(HST*)malloc(sizeof(HST)*hstsayisi);

    for(i=0; i<hstsayisi; i++)
    {
        printf(" %d. hastanin adini giriniz: ",i+1);
        scanf("%s",&((hastalar+i)->hasta_adi));
        printf(" %d. hastanin TC Kimlik numarasini giriniz: ",i+1);
        scanf("%lf",&(hastalar+i)->tc_no);
        ilacsayisi=0;
        printf(" %d. hastanin ilac sayisi kactir :",i+1);
        scanf("%d",&ilacsayisi);
        for(j=0; j<ilacsayisi; j++)
        {
            printf(" %d. hastanin %d. ilacinin adini giriniz:",i+1,j+1);
            scanf("%s",&((hastalar+i)->ilaclar+j)->ilac_adi);
            printf(" %d. hastanin %d. ilacinin turunu giriniz:",i+1,j+1);
            scanf("%s",&((hastalar+i)->ilaclar+j)->ilac_turu);
            printf(" %d. hastanin %d. ilacinin Firma adini giriniz:",i+1,j+1);
            scanf("%s",&((hastalar+i)->ilaclar+j)->firma_adi);
            printf(" %d. hastanin %d. ilacinin Kutu adedi giriniz:",i+1,j+1);
            scanf("%s",&((hastalar+i)->ilaclar+j)->kutu_adedi);
            printf(" %d. hastanin %d. ilacinin son kullanma tarihi giriniz(YYYY):",i+1,j+1);
            scanf("%d",&((hastalar+i)->ilaclar+j)->skt);
            printf(" %d. hastanin %d. ilacinin Fiyati giriniz:",i+1,j+1);
            scanf("%d",&((hastalar+i)->ilaclar+j)->fiyat);
        }

    }
    printf(" Ana Menuye dönmek ister misiniz \n 1-)EVET\t2-)HAYIR");
    scanf("%d",&cvp);
    printf("\n\n");
    if(cvp==1)
        maintwo();
    if(cvp==2)
        printf(" Isleminiz bitmistir.\nSaglikli gunler dileriz. ");
}


void guncelleme(int ilacsayisi)
{

    HST*hastalar;
    int cvp,i;
    ILC*ilaclar=(ILC*)realloc(ilaclar, sizeof(ILC)*ilacsayisi);
    printf(" Ilac bilgisimi(1) guncellemek istiyorsunuz\n hasta mi(2):");
    scanf("%d",&cvp);
    if(cvp==2)
    {
        printf(" Kacinci hastayi guncellemek istiyorsunuz :");
        scanf("%d",&i);
        printf(" %d. hastanin adini giriniz: ",i);
        scanf("%s",&((hastalar+i)->hasta_adi));
        printf(" %d. hastanin TC Kimlik numarasini giriniz: ",i);
        scanf("%lf",&(hastalar+i)->tc_no);
        printf(" %d. hastanin ilac sayisi kactir :",i);
        scanf("%d",&ilacsayisi);
    }
    if(cvp==1)
    {
        printf(" Kacinci ilaci guncellemek istiyorsunuz :");
        scanf("%d",&i);
        printf(" %d. Ilacin adi giriniz:",i);
        scanf("%s",&ilaclar[i].ilac_adi);
        printf(" %d. Ilacin turunu giriniz:",i);
        scanf("%s",&ilaclar[i].ilac_turu);
        printf(" %d. Ilacin Firma adini giriniz:",i);
        scanf("%s",&ilaclar[i].firma_adi);
        printf(" %d. Ilacin kutu adedi giriniz:",i);
        scanf("%d",&ilaclar[i].kutu_adedi);
        printf(" %d.Ilacin Son kullanma yilini giriniz(YYYY):",i);
        scanf("%d",&ilaclar[i].skt);
        printf(" %d. Ilacin fiyatini giriniz:",i);
        scanf("%d",&ilaclar[i].fiyat);
        printf(" Ana Menuye donmek ister misiniz \n 1-)EVET\t2-)HAYIR");
        scanf("%d",&cvp);
        printf("\n\n");
        if(cvp==1)

            main();

        if(cvp==2)

            printf(" Isleminiz bitmistir.\nSaglikli gunler dileriz. ");
    }
}

void listele(ilacsayisi)
{

    printf("\n");
    printf("--------LISTE--------\n");

    printf("Ilac sayisi:%d",ilacsayisi);
    ILC*ilaclar;

    for( i=0; i<ilacsayisi; i++)
    {

        printf("\n\n");
        printf(" %d. Ilacin  adi : %s\n",i+1,(ilaclar+i)->ilac_adi);
        printf(" %d. Ilacin turu : %s\n",i+1,ilaclar[i].ilac_turu);
        printf(" %d. Ilacin firma adi : %s\n",i+1,(ilaclar+i)->firma_adi);
        printf(" %d. Ilacin kutu adedi : %d\n",i+1,((ilaclar+i)->kutu_adedi));
        printf(" %d. Ilacin Son kullanma tarihi : %d\n",i+1,((ilaclar+i)->skt));
        printf(" %d. Ilacin fiyati : %d\n",i+1,((ilaclar+i)->fiyat));
        crp=((ilaclar+i)->kutu_adedi)*((ilaclar+i)->fiyat);
        printf("Toplam fiyat: %d*%dTL=%d",(ilaclar+i)->kutu_adedi,((ilaclar+i)->fiyat),crp);
    }

}

int reset()
{
    ILC*ilaclar;
    HST*hastalar;
    free(ilaclar);
    free(hastalar);
    printf(" Programiniz sifirlanmistir.");
    printf("\n");
    printf(" Saglikli gunler dileriz.");

}
