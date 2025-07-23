// tests/sales_test.cairo
#[cfg(test)]
mod tests {
    use super::*;
    use starknet::testing::Starknet;

    #[test]
    fn test_record_sale_multiple_items() {
        // Déployer le contrat (simulation locale)
        let mut starknet = Starknet::default();
        let contract = starknet.deploy(
            "src/lib.cairo",
            "SalesContract",
            // Pas d'arguments pour le constructeur ici, ou préciser selon la signature
            ()
        ).unwrap();

        // Préparation d'un acheteur fictif et d'une liste d'articles
        let buyer: felt252 = 0xAAA0.into(); // un felt quelconque
        let items = array![
            Item { id: 1_u128, price_ht: 100_u128 },
            Item { id: 2_u128, price_ht: 200_u128 }
        ];

        // Enregistrer une vente
        starknet.invoke(
            &contract,
            "record_sale",
            (buyer, items.clone())
        ).unwrap();

        // Vérifier que le compteur de ventes a augmenté à 1
        let count: u128 = starknet.call(&contract, "get_sale_count", ()).unwrap_json();
        assert_eq!(count, 1_u128);

        // Récupérer la vente enregistrée (ID = 0)
        let sale: Sale = starknet.call(&contract, "get_sale", (0_u128,)).unwrap_json();
        // Vérifier les totaux HT/TTC calculés correctement (20% de TVA)
        assert_eq!(sale.total_ht, 300_u128);         // 100+200
        assert_eq!(sale.tva_amount, 60_u128);        // 20% de 300
        assert_eq!(sale.total_ttc, 360_u128);        // 300+60
        // Vérifier l'acheteur et le nombre d'articles
        assert_eq!(sale.buyer, buyer);
        assert_eq!(sale.items.len(), 2usize);
        // Vérifier les articles individuels (id et prix)
        assert_eq!(sale.items.get(0).id, 1_u128);
        assert_eq!(sale.items.get(0).price_ht, 100_u128);
        assert_eq!(sale.items.get(1).id, 2_u128);
        assert_eq!(sale.items.get(1).price_ht, 200_u128);
    }
}
